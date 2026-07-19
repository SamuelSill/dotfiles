# General Instructions and Context

## Software Development

When writing any software in any language, follow the instructions below strictly:

### Writing Comments/Documentation/Commit Messages

When writing any form of documentation/commit message - you must be very concise.
Assume the readers are going to read the relevant code, and only explain the code on a very high-level,
mostly focusing on non-trivial decisions made in the design of the code, if the code doesn't explain itself.

Specifically for comments, you should avoid them completely unless absolutely necessary. Comments are usually a code smell,
indicating that the code isn't readable enough to explain itself - if you think of adding a comment, that probably indicates that the code should be cleaner and more readable.
The only justification for comments - is when the underlying algorithm is inherently difficult, and the code can't explain it by itself, or when the code is doing something
odd and unintuitive that requires justification.
