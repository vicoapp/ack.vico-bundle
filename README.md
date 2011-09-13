# Ack plugin for Vico

This plugin uses [Ack](http://betterthangrep.com/) to recursively search
the project directory.

Vico version 1.3 is required for this plugin to work.

## Key bindings

In normal mode:
&#x21E7;&#x2318;F -- Bring up the ack window, same as `:ack`.

In the file explorer:
&#x21E7;&#x2318;F -- Bring up the ack window with the selected folder as base search folder.

## Ex commands

- `:ack` -- Bring up the ack window.
- `:ack pattern` -- Bring up the ack window and search the project folder for pattern.
- `:aa` -- Go to the location of the current result.
- `:an[ext]` -- Go to the next result.
- `:ap[revious]` or `:aN[ext]` -- Go to the previous result.
- `:ar[ewind]` or `:afir[st]` -- Go to the first result.
- `:ala[st]` -- Go to the last result.
- `:anf[ile]` -- Go to the first result in the next file.
- `:apf[ile]` or `:aNf[ile]` -- Go to the last result in the previous file.

## Copyright

[Ack](http://github.com/petdance/ack) itself is Copyright 2005-2010 Andy Lester
under the terms of the Artistic License version 2.0.


Copyright (c) 2011 Martin Hedenfalk <martin@vicoapp.com>

Permission to use, copy, modify, and distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
