<?php
/**
 * Eurion Webmail – Calendar Plugin Configuration
 * Uses custom Eurion driver that syncs with the Eurion app calendar API.
 * Events are shared between the web app and webmail in real-time.
 */

// Use Eurion API driver (shared calendar with the Eurion web/desktop/mobile apps)
$config['calendar_driver'] = 'eurion';
$config['calendar_driver_default'] = 'eurion';

// Eurion API Gateway URL (inside Docker network)
$config['calendar_eurion_api_url'] = 'http://eurion-gateway:3000';

// Internal service secret (must match INTERNAL_SECRET env var on identity-service)
$config['calendar_eurion_internal_secret'] = 'eurion_internal_dev_secret';

// Default view and UI
$config['calendar_default_view'] = 'agendaWeek';
$config['calendar_timeslots'] = 4;
$config['calendar_first_day'] = 1;         // Monday
$config['calendar_first_hour'] = 8;
$config['calendar_work_start'] = 8;
$config['calendar_work_end'] = 17;
$config['calendar_event_coloring'] = 0;
$config['calendar_time_indicator'] = true;

// Default calendar name
$config['calendar_default_calendar'] = 'eurion-calendar';

// Contact birthdays from address book
$config['calendar_contact_birthdays'] = false;

// iTip invitation settings
$config['calendar_itip_send_option'] = 3;  // visible and active
$config['calendar_itip_after_action'] = 0; // no action after handling

// Free/busy
$config['calendar_freebusy_trigger'] = false;

// Resources
$config['calendar_resources_driver'] = '';
