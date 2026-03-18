<?php
/**
 * Eurion Calendar Driver for Roundcube
 *
 * Connects the Roundcube webmail calendar plugin to the Eurion Calendar API,
 * so events are shared between the Eurion web app and webmail.
 *
 * All CRUD operations go through the Eurion Gateway → identity-service.
 * Auth uses the same email/password the user logs into Roundcube with.
 *
 * @author Eurion Platform
 * @licence GNU AGPL
 */

require_once(__DIR__ . '/../calendar_driver.php');

class eurion_driver extends calendar_driver
{
    public $alarms      = true;
    public $attendees   = true;
    public $freebusy    = false;
    public $attachments = false;
    public $alarm_types = ['DISPLAY'];
    public $categoriesimmutable = false;

    private $rc;
    private $cal;
    private $cache       = [];
    private $calendars   = [];
    private $api_base;
    private $jwt_token   = null;
    private $jwt_expires = 0;
    private $refresh_token = null;
    private $user_email  = '';
    private $user_password = '';

    // Calendar color (Nord frost blue)
    const DEFAULT_COLOR = '5e81ac';
    const CALENDAR_ID   = 'eurion-calendar';

    /**
     * Constructor
     */
    public function __construct($cal)
    {
        $this->cal = $cal;
        $this->rc  = $cal->rc;

        // API base URL (gateway inside Docker network)
        $this->api_base = $this->rc->config->get('calendar_eurion_api_url', 'http://eurion-gateway:3000');

        // Load cached JWT from session
        $session_data = $_SESSION['eurion_calendar'] ?? [];
        if (!empty($session_data)) {
            $this->jwt_token     = $session_data['jwt'] ?? null;
            $this->jwt_expires   = $session_data['jwt_expires'] ?? 0;
            $this->refresh_token = $session_data['refresh_token'] ?? null;
        }

        // Set up virtual calendar representing the Eurion calendar
        $this->calendars[self::CALENDAR_ID] = [
            'id'         => self::CALENDAR_ID,
            'name'       => 'Eurion Calendar',
            'listname'   => 'Eurion Calendar',
            'editname'   => 'Eurion Calendar',
            'title'      => 'Eurion Calendar',
            'color'      => self::DEFAULT_COLOR,
            'showalarms' => true,
            'active'     => true,
            'editable'   => true,
            'default'    => true,
            'rights'     => 'lrswikxteav',
            'children'   => false,
            'group'      => '',
            'class'      => '',
            'virtual'    => false,
            'subscribed' => true,
            'activeonly'  => false,
        ];
    }

    // =========================================================================
    //  Authentication
    // =========================================================================

    /**
     * Authenticate against Eurion API and get JWT token.
     * Uses internal service-login endpoint (works for all users including SSO).
     * Falls back to regular login for local users if service-login fails.
     */
    private function ensure_auth()
    {
        // Already have a valid token
        if ($this->jwt_token && time() < ($this->jwt_expires - 30)) {
            return true;
        }

        // Try refresh first
        if ($this->refresh_token) {
            if ($this->refresh_jwt()) {
                return true;
            }
        }

        // Get user email from Roundcube session
        $email = $this->rc->get_user_name();
        if (empty($email)) {
            rcube::raise_error([
                'code' => 500,
                'message' => 'Eurion Calendar: No user email available'
            ], true, false);
            return false;
        }

        // Try service-login first (works for all users including SSO)
        $internal_secret = $this->rc->config->get('calendar_eurion_internal_secret', 'eurion_internal_dev_secret');
        $response = $this->api_request('POST', '/v1/auth/service-login', [
            'email' => $email,
        ], false, ['X-Internal-Secret: ' . $internal_secret]);

        // Fallback to regular login if service-login not available
        if (!$response || empty($response['data']['tokens']['accessToken'])) {
            $password = $this->rc->decrypt($_SESSION['password'] ?? '');
            if (!empty($password)) {
                $response = $this->api_request('POST', '/v1/auth/login', [
                    'email'    => $email,
                    'password' => $password,
                ], false);
            }
        }

        if ($response && !empty($response['data']['tokens']['accessToken'])) {
            $tokens = $response['data']['tokens'];
            $this->jwt_token     = $tokens['accessToken'];
            $this->refresh_token = $tokens['refreshToken'] ?? null;
            $this->jwt_expires   = time() + ($tokens['expiresIn'] ?? 900);

            // Cache in session
            $_SESSION['eurion_calendar'] = [
                'jwt'           => $this->jwt_token,
                'jwt_expires'   => $this->jwt_expires,
                'refresh_token' => $this->refresh_token,
            ];

            return true;
        }

        rcube::raise_error([
            'code' => 401,
            'message' => 'Eurion Calendar: Authentication failed for ' . $email
        ], true, false);
        return false;
    }

    /**
     * Refresh the JWT token using refresh token
     */
    private function refresh_jwt()
    {
        $response = $this->api_request('POST', '/v1/auth/refresh', [
            'refreshToken' => $this->refresh_token,
        ], false);

        if ($response && !empty($response['data']['tokens']['accessToken'])) {
            $tokens = $response['data']['tokens'];
            $this->jwt_token     = $tokens['accessToken'];
            $this->refresh_token = $tokens['refreshToken'] ?? $this->refresh_token;
            $this->jwt_expires   = time() + ($tokens['expiresIn'] ?? 900);

            $_SESSION['eurion_calendar'] = [
                'jwt'           => $this->jwt_token,
                'jwt_expires'   => $this->jwt_expires,
                'refresh_token' => $this->refresh_token,
            ];
            return true;
        }
        return false;
    }

    // =========================================================================
    //  HTTP Client
    // =========================================================================

    /**
     * Make an API request to the Eurion Gateway
     *
     * Uses curl for performance — file_get_contents has a 10-second IPv6 DNS
     * resolution timeout in Docker networks. curl with CURLOPT_IPRESOLVE_V4
     * resolves in <5ms.
     *
     * @param string $method  HTTP method
     * @param string $path    API path (e.g. /v1/calendar/events)
     * @param array  $data    Request body (for POST/PATCH/PUT)
     * @param bool   $auth    Include Authorization header
     * @param array  $extra_headers  Additional headers to include
     * @return array|null     Decoded JSON response or null on failure
     */
    private function api_request($method, $path, $data = null, $auth = true, $extra_headers = [])
    {
        $url = rtrim($this->api_base, '/') . $path;
        $has_body = ($data !== null && in_array(strtoupper($method), ['POST', 'PATCH', 'PUT']));

        $headers = [
            'Accept: application/json',
        ];

        // Only set Content-Type when sending a body — Fastify rejects
        // empty bodies with Content-Type: application/json (FST_ERR_CTP_EMPTY_JSON_BODY)
        if ($has_body) {
            $headers[] = 'Content-Type: application/json';
        }

        if ($auth && $this->jwt_token) {
            $headers[] = 'Authorization: Bearer ' . $this->jwt_token;
        }

        foreach ($extra_headers as $h) {
            $headers[] = $h;
        }

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => strtoupper($method),
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_TIMEOUT        => 5,
            CURLOPT_IPRESOLVE      => CURL_IPRESOLVE_V4,
        ]);

        if ($has_body) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }

        $response = curl_exec($ch);
        $errno    = curl_errno($ch);
        $error    = curl_error($ch);
        curl_close($ch);

        if ($errno || $response === false) {
            rcube::raise_error([
                'code' => 500,
                'message' => "Eurion Calendar API request failed: $method $url — $error"
            ], true, false);
            return null;
        }

        $decoded = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            return null;
        }

        return $decoded;
    }

    // =========================================================================
    //  Calendar CRUD
    // =========================================================================

    public function list_calendars($filter = 0)
    {
        return $this->calendars;
    }

    public function create_calendar($prop)
    {
        // Single calendar — no-op, return existing ID
        return self::CALENDAR_ID;
    }

    public function edit_calendar($prop)
    {
        // Allow color changes in memory
        if (isset($prop['color'])) {
            $this->calendars[self::CALENDAR_ID]['color'] = $prop['color'];
        }
        return true;
    }

    public function subscribe_calendar($prop)
    {
        if (isset($prop['active'])) {
            $this->calendars[self::CALENDAR_ID]['active'] = (bool)$prop['active'];
        }
        return true;
    }

    public function delete_calendar($prop)
    {
        return false; // Can't delete the Eurion calendar
    }

    public function search_calendars($query, $source)
    {
        return [];
    }

    // =========================================================================
    //  Event CRUD
    // =========================================================================

    /**
     * Create a new event.
     * If the event includes a video-conference URL field, or if the
     * calendar plugin signals a meeting, we auto-create an Eurion
     * meeting room + guest invite link and attach it to the event.
     */
    public function new_event($event)
    {
        if (!$this->ensure_auth()) return false;

        $body = $this->event_to_api($event);

        // Auto-create meeting link when:
        // - User types "meet" in the URL field (explicit trigger from webmail UI)
        // - User writes "eurion meet" in the location
        // - The special _meeting flag is set
        // NOTE: We do NOT auto-create for any title containing "meet" to avoid false positives.
        $url_val = strtolower(trim($event['url'] ?? ''));
        $wants_meeting = !empty($event['_meeting'])
                      || $url_val === 'meet'
                      || $url_val === 'eurion'
                      || $url_val === 'eurion meet'
                      || (stripos($event['location'] ?? '', 'eurion meet') !== false);

        if ($wants_meeting && empty($body['meetingUrl'])) {
            $meeting_url = $this->create_meeting_link($event['title'] ?? 'Meeting');
            if ($meeting_url) {
                $body['meetingUrl'] = $meeting_url;
                $body['location']  = $body['location'] ?: 'Eurion Meet';
                // Append link to description
                $desc = $body['description'] ?? '';
                $body['description'] = trim($desc . "\n\n📹 Join Eurion Meeting:\n" . $meeting_url);
            }
        }

        $response = $this->api_request('POST', '/v1/calendar/events', $body);

        if ($response && !empty($response['data']['id'])) {
            // Cache the created event for immediate get_event() calls
            $evt = $this->api_to_event($response['data']);
            $this->cache[$evt['id']] = $evt;

            // Also cache by the Roundcube-generated UID so that the
            // post-save get_event() call in calendar.php finds it.
            // Roundcube sets $event['id'] = $event['uid'] after new_event()
            // returns, then calls get_event() with that UID — which differs
            // from the Eurion API ID.
            if (!empty($event['uid']) && $event['uid'] !== $evt['id']) {
                $this->cache[$event['uid']] = $evt;
            }

            return $evt['id'];
        }

        return false;
    }

    /**
     * Update an existing event
     */
    public function edit_event($event)
    {
        if (!$this->ensure_auth()) return false;

        $id = $event['id'] ?? '';
        if (empty($id)) return false;

        $body = $this->event_to_api($event);
        $response = $this->api_request('PATCH', "/v1/calendar/events/{$id}", $body);

        return ($response && ($response['success'] ?? false));
    }

    /**
     * Move event (drag & drop in calendar — change start/end time)
     */
    public function move_event($event)
    {
        return $this->edit_event($event);
    }

    /**
     * Resize event (change duration)
     */
    public function resize_event($event)
    {
        return $this->edit_event($event);
    }

    /**
     * Remove an event
     */
    public function remove_event($event, $force = true)
    {
        if (!$this->ensure_auth()) return false;

        $id = $event['id'] ?? '';
        if (empty($id)) return false;

        $response = $this->api_request('DELETE', "/v1/calendar/events/{$id}");
        return ($response && ($response['success'] ?? false));
    }

    /**
     * Get a single event by ID or UID
     */
    public function get_event($event, $scope = 0, $full = false)
    {
        if (!$this->ensure_auth()) return null;

        $id = is_array($event) ? ($event['id'] ?? $event['uid'] ?? '') : $event;
        if (empty($id)) return null;

        // Check cache first (covers Roundcube UID → API event mapping from new_event)
        if (isset($this->cache[$id])) {
            return $this->cache[$id];
        }

        // Fetch single event by ID from API
        $response = $this->api_request('GET', "/v1/calendar/events/{$id}");
        if ($response && !empty($response['data']['id'])) {
            $evt = $this->api_to_event($response['data']);
            $this->cache[$evt['id']] = $evt;
            return $evt;
        }

        // If the event array already has enough data (e.g. just saved),
        // return it with the calendar ID set so _client_event() doesn't crash.
        if (is_array($event) && !empty($event['title'])) {
            $event['calendar'] = self::CALENDAR_ID;
            $event['uid']      = $event['uid'] ?? $id;
            return $event;
        }

        return null;
    }

    /**
     * Load events in a date range — this is the main query method
     */
    public function load_events($start, $end, $query = null, $calendars = null, $virtual = 1, $modifiedsince = null)
    {
        if (!$this->ensure_auth()) return [];

        // Convert unix timestamps to ISO 8601
        $params = [];
        if ($start) $params[] = 'start=' . urlencode(gmdate('Y-m-d\TH:i:s\Z', $start));
        if ($end)   $params[] = 'end='   . urlencode(gmdate('Y-m-d\TH:i:s\Z', $end));

        $qs = !empty($params) ? '?' . implode('&', $params) : '';
        $response = $this->api_request('GET', "/v1/calendar/events{$qs}");

        if (!$response || empty($response['data'])) {
            return [];
        }

        // API returns { data: { events: [...] } }
        $api_events = $response['data']['events'] ?? $response['data'];
        if (!is_array($api_events)) return [];

        $events = [];
        foreach ($api_events as $api_event) {
            $evt = $this->api_to_event($api_event);

            // Filter by search query if provided
            if ($query) {
                $q = mb_strtolower($query);
                $match = mb_strpos(mb_strtolower($evt['title'] ?? ''), $q) !== false
                      || mb_strpos(mb_strtolower($evt['description'] ?? ''), $q) !== false
                      || mb_strpos(mb_strtolower($evt['location'] ?? ''), $q) !== false;
                if (!$match) continue;
            }

            $events[] = $evt;
            $this->cache[$evt['id']] = $evt;
        }

        return $events;
    }

    /**
     * Count events per calendar in a date range
     */
    public function count_events($calendars, $start, $end = null)
    {
        $events = $this->load_events($start, $end);
        return [self::CALENDAR_ID => count($events)];
    }

    // =========================================================================
    //  Alarms
    // =========================================================================

    public function pending_alarms($time, $calendars = null)
    {
        return [];
    }

    public function dismiss_alarm($event_id, $snooze = 0)
    {
        return true;
    }

    // =========================================================================
    //  Meeting Link Creation
    // =========================================================================

    /**
     * Create an Eurion meeting room + guest invite link.
     * Returns the shareable meeting URL, or null on failure.
     */
    private function create_meeting_link($title)
    {
        if (!$this->ensure_auth()) return null;

        // Step 1: Create a messaging room for the meeting
        $room_body = [
            'name'  => $title,
            'type'  => 'group',
            'topic' => 'Meeting: ' . $title,
        ];
        $room_res = $this->api_request('POST', '/v1/rooms', $room_body);

        if (!$room_res || empty($room_res['id'])) {
            // Try alternative response shape
            $room_id = $room_res['data']['id'] ?? $room_res['id'] ?? null;
            if (!$room_id) {
                rcube::raise_error([
                    'message' => 'Eurion: Failed to create meeting room',
                    'type'    => 'php',
                ], true, false);
                return null;
            }
        } else {
            $room_id = $room_res['id'];
        }

        // Step 2: Create a guest invite for the room
        $invite_body = [
            'roomId'         => $room_id,
            'guestName'      => 'Meeting Participant',
            'canChat'        => true,
            'canVideo'       => true,
            'canScreenShare' => true,
            'canUploadFiles' => false,
            'maxUses'        => 0, // unlimited
        ];
        $invite_res = $this->api_request('POST', '/v1/guest/invite', $invite_body);

        if ($invite_res && !empty($invite_res['data']['link'])) {
            return $invite_res['data']['link'];
        }
        // Try alternative shape
        if ($invite_res && !empty($invite_res['link'])) {
            return $invite_res['link'];
        }

        rcube::raise_error([
            'message' => 'Eurion: Failed to create guest invite link',
            'type'    => 'php',
        ], true, false);
        return null;
    }

    // =========================================================================
    //  Data Mapping: Eurion API ↔ Roundcube Event
    // =========================================================================

    /**
     * Convert Roundcube event array → Eurion API request body
     */
    private function event_to_api($event)
    {
        $body = [];

        if (isset($event['title']))       $body['title']       = $event['title'];
        if (isset($event['description'])) $body['description'] = $event['description'];
        if (isset($event['location']))    $body['location']    = $event['location'];

        // Dates: Roundcube uses DateTimeImmutable, API expects ISO 8601
        if (isset($event['start']) && $event['start'] instanceof \DateTimeInterface) {
            $body['startTime'] = $event['start']->format('c');
        }
        if (isset($event['end']) && $event['end'] instanceof \DateTimeInterface) {
            $body['endTime'] = $event['end']->format('c');
        }

        // All-day flag
        if (isset($event['allday'])) {
            $body['allDay'] = (bool) $event['allday'];
        }

        // Privacy
        if (isset($event['sensitivity'])) {
            $body['isPrivate'] = ($event['sensitivity'] === 'private' || $event['sensitivity'] === 'confidential');
        }

        // Color
        if (isset($event['color'])) {
            $body['color'] = '#' . ltrim($event['color'], '#');
        }

        // Attendees
        if (isset($event['attendees']) && is_array($event['attendees'])) {
            $body['attendees'] = [];
            foreach ($event['attendees'] as $att) {
                if (!empty($att['email'])) {
                    $body['attendees'][] = [
                        'email'  => $att['email'],
                        'name'   => $att['name'] ?? '',
                        'status' => $this->map_rsvp_to_api($att['status'] ?? 'NEEDS-ACTION'),
                    ];
                }
            }
        }

        // Meeting URL (pass through if already set)
        if (!empty($event['url'])) {
            $body['meetingUrl'] = $event['url'];
        }

        return $body;
    }

    /**
     * Convert Eurion API event → Roundcube event array
     */
    private function api_to_event($api)
    {
        $event = [
            'id'          => $api['id'],
            'uid'         => $api['id'],
            'calendar'    => self::CALENDAR_ID,
            'title'       => $api['title'] ?? '(No title)',
            'description' => $api['description'] ?? '',
            'location'    => $api['location'] ?? '',
            'allday'      => (bool)($api['all_day'] ?? $api['allDay'] ?? false),
            'free_busy'   => 'busy',
            'status'      => 'CONFIRMED',
            'priority'    => 0,
            'sensitivity' => (!empty($api['is_private']) || !empty($api['isPrivate'])) ? 'private' : 'public',
            'changed'     => new \DateTimeImmutable($api['updated_at'] ?? $api['updatedAt'] ?? 'now'),
            'created'     => new \DateTimeImmutable($api['created_at'] ?? $api['createdAt'] ?? 'now'),
            // Fields required by Roundcube _client_event() to avoid undefined key warnings
            'valarms'     => null,
            'recurrence'  => null,
            'attachments' => [],
            'links'       => [],
            'className'   => '',
            'url'         => '',
            'organizer'   => null,
            'categories'  => [],
            'recurrence_id' => null,
        ];

        // Parse dates
        $start_str = $api['start_time'] ?? $api['startTime'] ?? null;
        $end_str   = $api['end_time']   ?? $api['endTime']   ?? null;

        if ($start_str) {
            $event['start'] = new \DateTimeImmutable($start_str);
        }
        if ($end_str) {
            $event['end'] = new \DateTimeImmutable($end_str);
        }

        // Attendees
        $attendees_raw = $api['attendees'] ?? [];
        if (is_string($attendees_raw)) {
            $attendees_raw = json_decode($attendees_raw, true) ?: [];
        }
        $event['attendees'] = [];
        foreach ($attendees_raw as $att) {
            $event['attendees'][] = [
                'name'   => $att['name'] ?? '',
                'email'  => $att['email'] ?? '',
                'role'   => 'REQ-PARTICIPANT',
                'status' => $this->map_rsvp_from_api($att['status'] ?? 'pending'),
            ];
        }

        // Color (strip # for Roundcube)
        if (!empty($api['color'])) {
            $event['color'] = ltrim($api['color'], '#');
        }

        // Meeting URL
        if (!empty($api['meeting_url'] ?? $api['meetingUrl'] ?? null)) {
            $event['url'] = $api['meeting_url'] ?? $api['meetingUrl'];
        }

        return $event;
    }

    /**
     * Map Roundcube RSVP status → Eurion API status
     */
    private function map_rsvp_to_api($status)
    {
        $map = [
            'ACCEPTED'     => 'accepted',
            'DECLINED'     => 'declined',
            'TENTATIVE'    => 'tentative',
            'NEEDS-ACTION' => 'pending',
            'UNKNOWN'      => 'pending',
        ];
        return $map[strtoupper($status)] ?? 'pending';
    }

    /**
     * Map Eurion API RSVP status → Roundcube status
     */
    private function map_rsvp_from_api($status)
    {
        $map = [
            'accepted'  => 'ACCEPTED',
            'declined'  => 'DECLINED',
            'tentative' => 'TENTATIVE',
            'pending'   => 'NEEDS-ACTION',
        ];
        return $map[strtolower($status)] ?? 'NEEDS-ACTION';
    }

    // =========================================================================
    //  Inherited public methods (provide sensible defaults)
    // =========================================================================

    public function unserialize_attendees($s_attendees)
    {
        if (is_array($s_attendees)) return $s_attendees;
        if (is_string($s_attendees)) {
            $decoded = json_decode($s_attendees, true);
            return is_array($decoded) ? $decoded : [];
        }
        return [];
    }

    public function calendar_form($action, $calendar, $formfields)
    {
        // Return empty — we don't allow editing the calendar itself
        return '';
    }
}
