**IMPORTANT:** You must follow the following guidelines strictly. Failing to follow any of them would result in
incorrect outcome, which is not acceptable.

# General Instructions and Context

## Software Development

When writing any software in any language, follow the instructions below strictly:

### Clean Code

Always strive to prioritize clean, readable and straightforward code - even at the cost of performance in cases where it isn't important.

This comes into practice in multiple ways:

* Keep functions short - if a block of code gets too long, turn it into a separate function. A reader should understand any function's implementation after a brief read.
* Keep indentation at a minimum - utilize early returns, and utility functions for keeping the code parsable, without too much mental strain.

### Formatting / Style

In general, always follow the surrounding code's style strictly, even if it contradicts my own preferences.
However, when there is no clear preference/guideline in the surrounding code:

Always have a blank line:
* Before a comment.
* Before a return statement.
* After a code block is closed, unless it's followed by another block close, for example:
```c
if (condition) {
}
int var; // BAD! There should be a newline before this line.

while (condition1) {
    if (condition2) {
    }
} // GOOD! There should be no newline before this line.
```

### Naming Conventions

* Never abbreviate any name in the code, unless the abbreviation is a known term (like http, mcp, etc.) -
Instead, name the variable/function/etc. in a self-explanatory descriptive way. The only exceptions to this rule are `i/j` for indices,
and when implementing mathematical formulae or algorithms with well-known symbol names.
* Never specify the type/data structure of a variable in its name, unless it's the standard for the surrounding
variables/members (i.e in low-level OS code). For example, instead of `number_list`, call it `numbers`.

### Writing Comments/Documentation/Commit Messages

#### What to comment:

When writing any form of documentation/commit message - you must be very concise.
Assume the readers are going to read the relevant code, and only explain the code on a very high-level,
mostly focusing on non-trivial decisions made in the design of the code, if the code doesn't explain itself.

Never specify in comments/docs any outdated older implementation details that are no longer relevant or present.
Comments/docs should describe just the current state of what they're documenting - never a history lesson, never an explanation of how we got here - unless
we chose a solution that is not the immediate most inuitive one, in which case we can justify via specifying why we dropped the inuitive approach.

#### When to Comment:

Specifically for comments, you should **avoid them completely** unless absolutely necessary. Comments are usually a code smell,
indicating that the code isn't readable enough to explain itself - if you think of adding a comment, it probably indicates that the code should be cleaner and more readable.
The justification for comments:
* When the underlying algorithm is inherently difficult, and the code can't explain it by itself, or when the code is doing something
odd and unintuitive that requires justification.
* When documenting functions/classes/structs/impls/members/etc. - if the name doesn't already explain itself (and it's difficult to think of a name that does),
a 1-2 liner comment explaining the purpose of the construct would be helpful
