-- EURION Database Init Script
-- Runs once on first PostgreSQL startup
-- Creates all service databases owned by the eurion user

CREATE DATABASE eurion_identity;
CREATE DATABASE eurion_org;
CREATE DATABASE eurion_audit;
CREATE DATABASE eurion_messaging;
CREATE DATABASE eurion_file;
CREATE DATABASE eurion_video;
CREATE DATABASE eurion_notification;
CREATE DATABASE eurion_admin;
CREATE DATABASE eurion_search;
CREATE DATABASE eurion_workflow;
CREATE DATABASE eurion_preview;
CREATE DATABASE eurion_ai;
CREATE DATABASE eurion_transcription;
CREATE DATABASE eurion_bridge;

GRANT ALL PRIVILEGES ON DATABASE eurion_identity TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_org TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_audit TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_messaging TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_file TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_video TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_notification TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_admin TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_search TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_workflow TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_preview TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_ai TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_transcription TO eurion;
GRANT ALL PRIVILEGES ON DATABASE eurion_bridge TO eurion;
