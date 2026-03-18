CREATE TABLE IF NOT EXISTS caldav_calendars (
  calendar_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL,
  color TEXT NOT NULL,
  showalarms INTEGER NOT NULL DEFAULT 1,
  caldav_url TEXT DEFAULT NULL,
  caldav_tag TEXT DEFAULT NULL,
  caldav_user TEXT DEFAULT NULL,
  caldav_pass TEXT DEFAULT NULL,
  caldav_oauth_provider TEXT DEFAULT NULL,
  readonly INTEGER NOT NULL DEFAULT 0,
  caldav_last_change TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS caldav_user_name_idx ON caldav_calendars(user_id, name);
CREATE TABLE IF NOT EXISTS caldav_events (
  event_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  calendar_id INTEGER NOT NULL DEFAULT 0,
  recurrence_id INTEGER NOT NULL DEFAULT 0,
  uid TEXT NOT NULL DEFAULT '',
  instance TEXT NOT NULL DEFAULT '',
  isexception INTEGER NOT NULL DEFAULT 0,
  created DATETIME NOT NULL DEFAULT '1000-01-01 00:00:00',
  changed DATETIME NOT NULL DEFAULT '1000-01-01 00:00:00',
  sequence INTEGER NOT NULL DEFAULT 0,
  start DATETIME NOT NULL DEFAULT '1000-01-01 00:00:00',
  end DATETIME NOT NULL DEFAULT '1000-01-01 00:00:00',
  recurrence TEXT DEFAULT NULL,
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  categories TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  all_day INTEGER NOT NULL DEFAULT 0,
  free_busy INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 0,
  sensitivity INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT '',
  alarms TEXT DEFAULT NULL,
  attendees TEXT DEFAULT NULL,
  notifyat DATETIME DEFAULT NULL,
  caldav_url TEXT NOT NULL DEFAULT '',
  caldav_tag TEXT DEFAULT NULL,
  caldav_last_change TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (calendar_id) REFERENCES caldav_calendars(calendar_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS caldav_uid_idx ON caldav_events(uid);
CREATE INDEX IF NOT EXISTS caldav_recurrence_idx ON caldav_events(recurrence_id);
CREATE INDEX IF NOT EXISTS caldav_calendar_notify_idx ON caldav_events(calendar_id, notifyat);
CREATE TABLE IF NOT EXISTS itipinvitations (
  token TEXT NOT NULL,
  event_uid TEXT NOT NULL,
  user_id INTEGER NOT NULL DEFAULT 0,
  event TEXT NOT NULL,
  expires DATETIME DEFAULT NULL,
  cancelled INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(token)
);
CREATE INDEX IF NOT EXISTS itip_uid_idx ON itipinvitations(event_uid, user_id);
