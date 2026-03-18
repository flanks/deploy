#!/bin/bash
# Roundcube post-setup task: ensure full file sync + calendar plugin + DB tables
# This runs AFTER the entrypoint has copied Roundcube files to /var/www/html

DOCROOT="/var/www/html"
SRCROOT="/usr/src/roundcubemail"

echo "[eurion] Post-setup starting..."

# Ensure ALL files from source are synced (fix incomplete copy on same-version restart)
# The entrypoint sometimes skips files when it detects same version
echo "[eurion] Ensuring full file sync from source..."
cp -rn "$SRCROOT"/* "$DOCROOT/" 2>/dev/null || true
chown -R www-data:www-data "$DOCROOT" 2>/dev/null || true

# Verify public_html exists (Apache DocumentRoot)
if [ -d "$DOCROOT/public_html" ]; then
    echo "[eurion] public_html directory OK."
else
    echo "[eurion] ERROR: public_html missing after sync!"
fi

# Sync calendar plugin files from source to docroot (installto.sh doesn't copy new plugins)
for plugin in calendar libcalendaring libkolab; do
    if [ -d "$SRCROOT/plugins/$plugin" ]; then
        if [ ! -f "$DOCROOT/plugins/$plugin/${plugin}.php" ]; then
            echo "[eurion] Copying $plugin plugin to docroot..."
            mkdir -p "$DOCROOT/plugins/$plugin"
            cp -rf "$SRCROOT/plugins/$plugin/"* "$DOCROOT/plugins/$plugin/"
            chown -R www-data:www-data "$DOCROOT/plugins/$plugin" 2>/dev/null || true
        else
            echo "[eurion] Plugin $plugin already exists in docroot."
        fi
    fi
done

# Sync sabre/dav and other vendor dependencies needed by calendar
if [ -d "$SRCROOT/vendor/sabre" ] && [ ! -d "$DOCROOT/vendor/sabre" ]; then
    echo "[eurion] Syncing vendor dependencies (sabre/dav etc.)..."
    cp -rf "$SRCROOT/vendor/sabre" "$DOCROOT/vendor/" 2>/dev/null || true
    cp -rf "$SRCROOT/vendor/psr" "$DOCROOT/vendor/" 2>/dev/null || true
    # Regenerate autoload
    cp -f "$SRCROOT/vendor/autoload.php" "$DOCROOT/vendor/autoload.php" 2>/dev/null || true
    cp -rf "$SRCROOT/vendor/composer" "$DOCROOT/vendor/" 2>/dev/null || true
fi

# Initialize calendar DB tables
SQLITE_DB="/var/roundcube/db/sqlite.db"

if [ -f "$SQLITE_DB" ]; then
    # Initialize caldav tables (used by caldav/ical drivers and shared schema)
    TABLE_EXISTS=$(sqlite3 "$SQLITE_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='caldav_calendars';" 2>/dev/null || echo "0")
    if [ "$TABLE_EXISTS" = "0" ] || [ -z "$TABLE_EXISTS" ]; then
        echo "[eurion] Initializing calendar database tables (caldav/ical)..."
        SQL_FILE="$DOCROOT/plugins/calendar/SQL/sqlite_fixed.sql"
        if [ -f "$SQL_FILE" ]; then
            sqlite3 "$SQLITE_DB" ".read $SQL_FILE" 2>&1 || echo "[eurion] Warning: calendar SQL init had issues"
            echo "[eurion] Calendar tables initialized."
        else
            echo "[eurion] Warning: Fixed SQL file not found at $SQL_FILE"
        fi
    else
        echo "[eurion] Calendar caldav tables already exist."
    fi

    # Initialize database driver tables (used by 'database' calendar driver)
    DB_TABLE_EXISTS=$(sqlite3 "$SQLITE_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='database_calendars';" 2>/dev/null || echo "0")
    if [ "$DB_TABLE_EXISTS" = "0" ] || [ -z "$DB_TABLE_EXISTS" ]; then
        echo "[eurion] Creating database driver tables..."
        sqlite3 "$SQLITE_DB" "CREATE TABLE IF NOT EXISTS database_calendars (
            calendar_id INTEGER PRIMARY KEY NOT NULL,
            user_id INTEGER NOT NULL DEFAULT 0,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            showalarms INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
        );"
        sqlite3 "$SQLITE_DB" "CREATE INDEX IF NOT EXISTS user_name_idx ON database_calendars(user_id, name);"
        sqlite3 "$SQLITE_DB" "CREATE TABLE IF NOT EXISTS database_events (
            event_id INTEGER PRIMARY KEY NOT NULL,
            calendar_id INTEGER NOT NULL DEFAULT 0,
            recurrence_id INTEGER NOT NULL DEFAULT 0,
            uid TEXT NOT NULL DEFAULT '',
            instance TEXT NOT NULL DEFAULT '',
            isexception INTEGER NOT NULL DEFAULT 0,
            created datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
            changed datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
            sequence INTEGER NOT NULL DEFAULT 0,
            start datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
            end datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
            recurrence TEXT DEFAULT NULL,
            title TEXT NOT NULL,
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
            notifyat datetime DEFAULT NULL,
            FOREIGN KEY (calendar_id) REFERENCES database_calendars(calendar_id) ON DELETE CASCADE ON UPDATE CASCADE
        );"
        sqlite3 "$SQLITE_DB" "CREATE INDEX IF NOT EXISTS uid_idx ON database_events(uid);"
        sqlite3 "$SQLITE_DB" "CREATE INDEX IF NOT EXISTS recurrence_idx ON database_events(recurrence_id);"
        sqlite3 "$SQLITE_DB" "CREATE INDEX IF NOT EXISTS calendar_notify_idx ON database_events(calendar_id, notifyat);"
        sqlite3 "$SQLITE_DB" "CREATE TABLE IF NOT EXISTS database_attachments (
            attachment_id INTEGER PRIMARY KEY NOT NULL,
            event_id INTEGER NOT NULL DEFAULT 0,
            filename TEXT NOT NULL DEFAULT '',
            mimetype TEXT NOT NULL DEFAULT '',
            size INTEGER NOT NULL DEFAULT 0,
            data TEXT NOT NULL DEFAULT '',
            FOREIGN KEY (event_id) REFERENCES database_events(event_id) ON DELETE CASCADE ON UPDATE CASCADE
        );"
        echo "[eurion] Database driver tables created."
    else
        echo "[eurion] Database driver tables already exist."
    fi
else
    echo "[eurion] Warning: SQLite DB not found — tables will be created on first access."
fi

echo "[eurion] Calendar plugin post-setup complete."
