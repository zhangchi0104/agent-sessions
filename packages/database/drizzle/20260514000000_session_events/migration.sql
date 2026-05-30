CREATE TABLE `session_events` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `session_id` text,
  `event_name` text NOT NULL,
  `tool_name` text,
  `cwd` text,
  `payload` text NOT NULL,
  `created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `session_events_session_id_idx` ON `session_events` (`session_id`);
--> statement-breakpoint
CREATE INDEX `session_events_event_name_idx` ON `session_events` (`event_name`);
--> statement-breakpoint
CREATE INDEX `session_events_created_at_idx` ON `session_events` (`created_at`);
