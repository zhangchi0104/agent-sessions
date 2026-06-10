CREATE TABLE `sessions` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `session_id` text NOT NULL,
  `status` text DEFAULT 'IDLE' NOT NULL,
  `agent` text NOT NULL,
  `session_name` text NOT NULL,
  `working_directory` text NOT NULL,
  `created_at` integer NOT NULL,
  `updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `sessions_session_id_unique` ON `sessions` (`session_id`);
