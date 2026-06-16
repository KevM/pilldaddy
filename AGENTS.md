# Guidelines for Coding Agents

This project contains rules and expectations for any agentic AI developers assisting with this codebase.

## Core Rules

1. **Always Verify Builds**: The application **must** always be buildable and compile successfully before you consider any task completed.
2. **Compile-Test Locally**: Do not rely on assumptions. Always execute the compiler (e.g. `xcodebuild` or equivalent local build tool) to verify that all files compile and link cleanly.
3. **Handle Project Configurations**: If using `XcodeGen` or other project configuration generators, always run `xcodegen generate` or equivalent after creating, deleting, or moving files, and verify that the target compiles after generation.
4. **No Placeholders**: Never introduce uncompilable code, missing imports, or empty placeholder methods.
