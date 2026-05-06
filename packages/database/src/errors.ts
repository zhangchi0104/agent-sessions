import * as Schema from "effect/Schema";

export class DrizzleError extends Schema.TaggedErrorClass<DrizzleError>()("DrizzleError", {
  message: Schema.String,
  cause: Schema.Defect,
}) {
  static fromUnknown(error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return new DrizzleError({ message, cause: error });
  }
}
