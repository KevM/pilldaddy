# Guidelines for Coding Agents

This project contains rules and expectations for any agentic AI developers assisting with this codebase.

## Core Rules

1. **Always Verify Builds**: The application **must** always be buildable and compile successfully before you consider any task completed.
2. **Compile-Test Locally**: Do not rely on assumptions. Always execute the compiler (e.g. `xcodebuild` or equivalent local build tool) to verify that all files compile and link cleanly.
3. **Handle Project Configurations**: If using `XcodeGen` or other project configuration generators, always run `xcodegen generate` or equivalent after creating, deleting, or moving files, and verify that the target compiles after generation.
4. **No Placeholders**: Never introduce uncompilable code, missing imports, or empty placeholder methods.
5. **Local Git Commits**: Always commit changes locally at the end of each task or when asked to implement a plan.
6. **Swift Testing**: Always write new tests using the modern `Swift Testing` framework (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`) instead of `XCTest`. Do not use `XCTestCase` subclassing or import `XCTest`.
7. **Simulator**: When building or testing against the iOS Simulator, use **iPhone 17** as the destination (e.g. `-destination 'platform=iOS Simulator,name=iPhone 17'`).


