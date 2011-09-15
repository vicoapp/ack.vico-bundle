; Copyright (c) 2011 Martin Hedenfalk <martin@vicoapp.com>
;
; Permission to use, copy, modify, and distribute this software for any
; purpose with or without fee is hereby granted, provided that the above
; copyright notice and this permission notice appear in all copies.
;
; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

; Create a key map for the results table
(set ackmap (ViMap mapWithName:"ackMap"))
(ackmap include:(ViMap mapWithName:"tableNavigationMap"))
(ackmap setKey:"<cr>" toAction:"gotoResult:")
(ackmap setKey:"s" toAction:"splitOpen:")
(ackmap setKey:"v" toAction:"vsplitOpen:")
(ackmap setKey:"<tab>" toAction:"focusNextKeyView:")
(ackmap setKey:"<shift-tab>" toAction:"focusNextKeyView:")
(ackmap setKey:"<shift-ctrl-y>" toAction:"focusNextKeyView:")
(ackmap setKey:"<esc>" toAction:"focusDocument:")
(ackmap setKey:"/" toAction:"filter:")

(class AckTableView is NSTableView
    (ivar (id) keyManager)

    (- (void)awakeFromNib is
        (set @keyManager ((ViKeyManager alloc) initWithTarget:self defaultMap:ackmap)))

    ; Pass key events to the key manager
    (- (void)keyDown:(id)event is (@keyManager keyDown:event))
    (- (BOOL)performKeyEquivalent:(id)event is
        (if (eq ((self window) firstResponder) self)
            (@keyManager performKeyEquivalent:event)
            (else NO)))

    (- (id)keyManager:(id)keyManager evaluateCommand:(id)command is
        (if (set target (self targetForSelector:(command action)))
            (target performSelector:(command action) withObject:command)))

    (- (BOOL)focusNextKeyView:(id)command is ((self window) selectNextKeyView:self))
    (- (BOOL)focusDocument:(id)command is ((current-window) showWindow:nil)) )


(class AckResultsController is NSWindowController
    (ivar (id) tableView (id) arrayController (id) task (id) stream (id) baseURL (id) matchedFiles
          (id) initialPattern (id) spinner (id) startStopButton (id) searchPattern (id) searchOptions
          (BOOL) closeOnFinish (id) folderLabel (id) infoLabel (id) filterField
          (id) optIgnoreCase (id) optSmartCase (id) optLiteralMatch
          (id) optWholeWords (id) optFollowSymlinks (id) markStack)

    (+ (id)ackInURL:(id)aURL forPattern:(id)pattern is
        (if $sharedAckResultsController
            (($sharedAckResultsController nextRunloop) showWindow:nil)
            ($sharedAckResultsController setBaseURL:aURL)
            (if pattern ($sharedAckResultsController searchPattern:pattern
                withOptions:($sharedAckResultsController searchOptions)))
            (else (set $sharedAckResultsController ((self alloc) initWithBaseURL:aURL pattern:pattern)) )))

    (- (id)searchOptions is (@searchOptions objectValue))
    (- (void)setBaseURL:(id)aURL is
        (set @baseURL aURL)
        ((self window) makeFirstResponder:@searchPattern)
        (@folderLabel setStringValue:"Search in folder #{(@baseURL displayString)}"))

    (- (id)initWithBaseURL:(id)aURL pattern:(id)pattern is
        (set @baseURL aURL)
        (super initWithWindowNibPath:"#{bundlePath}/AckResults.nib" owner:self)
        (set @initialPattern pattern)
        (set @markStack (mark-manager stackWithName:"Ack Results"))
        ;(@markStack pop)
        ((self nextRunloop) showWindow:nil)
        self)

    (- (void)windowDidLoad is
        (@folderLabel setStringValue:"Search in folder #{(@baseURL displayString)}")
        (@infoLabel setStringValue:"")
        (@arrayController setObjectClass:(ViMark class))
        (@arrayController bind:"contentArray" toObject:@markStack withKeyPath:"list.marks" options:nil)
        (@arrayController bind:"selectionIndexes" toObject:@markStack withKeyPath:"list.selectionIndexes" options:nil)
        ; Set colors to match the current theme.
        ; (@tableView setBackgroundColor:((ViThemeStore defaultTheme) backgroundColor))
        ; (@searchPattern setBackgroundColor:((ViThemeStore defaultTheme) backgroundColor))
        ; (@searchPattern setTextColor:((ViThemeStore defaultTheme) foregroundColor))
        (@searchPattern setFont:(ViThemeStore font))
        ((@tableView tableColumns) each:(do (tc)
        ; ((tc dataCell) setTextColor:((ViThemeStore defaultTheme) foregroundColor))
          ((tc dataCell) setFont:(ViThemeStore font)) ))
        (@tableView setDelegate:self)
        (@tableView setDoubleAction:"gotoResult:")
        ; FIXME: should remember the settings in NSUserDefaults
        (@optIgnoreCase setState:((user-defaults) boolForKey:"ignorecase"))
        (@optSmartCase setState:((user-defaults) boolForKey:"smartcase"))
        (@searchOptions setTokenizingCharacterSet:(NSCharacterSet whitespaceAndNewlineCharacterSet))
        (if @initialPattern (self searchPattern:@initialPattern withOptions:nil)))

    ; conditionally enable the search button
    (- (void)enableSearchButton is (@startStopButton setEnabled:(gt ((@searchPattern stringValue) length) 0)))
    (- (void)controlTextDidChange:(id)notification is (self enableSearchButton))

    ; Terminate ack when window closes.
    (- (BOOL)windowShouldClose:(id)sender is
        (if (@task isRunning)
            ; (NSLog "sending SIGTERM to pid #{(@task processIdentifier)}")
            (@task terminate)
            (set @closeOnFinish YES)
            NO ; Don't close window now, wait until ack has terminated.
            (else YES)))

    ; Assumes output is UTF-8 and that we read data chunks on newline boundaries.
    (- (void)parse:(id)data is
        ; (NSLog "got #{(data length)} bytes of data from ack")
        (set string ((NSString alloc) initWithData:data encoding:NSUTF8StringEncoding))
        ((string lines) each:(do (line)
            (set match (/^(.{1,256}):(\d+):(.+)$/ findInString:line))
            (if (eq (match count) 4)
                (set url (@baseURL URLByAppendingPathComponent:(match groupAtIndex:1)))
                (@matchedFiles addObject:url)
                (set line ((match groupAtIndex:2) integerValue))
                (set mark (ViMark markWithURL:url name:nil title:(match groupAtIndex:3) line:line column:0))
                ((@markStack list) addMark:mark)
                ;(NSLog "got mark #{(mark description)}")
                )))
        (self updateInfoLabel))

    (- (void)updateInfoLabel is
        (@infoLabel setStringValue:"#{((@arrayController arrangedObjects) count)} matched lines in #{(@matchedFiles count)} files."))

    (- (void)finish is
        ; (NSLog "waiting for ack to exit...")
        (@task waitUntilExit)
        (@spinner stopAnimation:nil)
        (@searchPattern setEnabled:YES)
        (self enableSearchButton)
        (@startStopButton setTitle:"Search")
        (@folderLabel setStringValue:"Search finished in folder #{(@baseURL displayString)}")
        (set status (@task terminationStatus))
        ; (NSLog "ack exited with status #{status}")
        (@stream close)
        (set @task nil)
        (if (@closeOnFinish) (self close)))

    ; stream delegate method
    (- (void)stream:(id)stream handleEvent:(int)event is
        (case event
            (NSStreamEventHasBytesAvailable (self parse:(stream data)))
            (NSStreamEventHasSpaceAvailable (stream shutdownWrite))
            (NSStreamEventErrorOccurred (self finish))
            (NSStreamEventEndEncountered (self finish))))

    (- (void)startStop:(id)sender is
        (if (@task)
            (@task terminate)
            (else (self searchPattern:(@searchPattern stringValue) withOptions:(@searchOptions objectValue)))))

    (- (id)searchPattern:(id)pattern withOptions:(id)options is
        (@folderLabel setStringValue:"Searching in folder #{(@baseURL displayString)}...")
        ((self window) setTitle:"Ack: #{pattern}")
        ((@markStack list) clear)
        ;(@markStack makeList)
        (set @matchedFiles (NSMutableSet set))
        (self updateInfoLabel)
        (@spinner startAnimation:nil)
        (@searchPattern setStringValue:pattern)
        (@searchPattern setEnabled:NO)
        (@startStopButton setTitle:"Stop")
        (@filterField setStringValue:"")
        (self filterResults:@filterField)
        ((self window) makeFirstResponder:@tableView)
        ; launch Ack
        (set @task ((NSTask alloc) init))
        (@task setLaunchPath:"#{bundlePath}/ack")
        (set arguments (NSMutableArray arrayWithObject:"--flush"))
        (if (@optSmartCase state) (arguments addObject:"--smart-case")
            (else (if (@optIgnoreCase state) (arguments addObject:"--ignore-case"))))
        (if (@optWholeWords state) (arguments addObject:"--word-regexp"))
        (if (@optLiteralMatch state) (arguments addObject:"--literal"))
        (if (@optFollowSymlinks state) (arguments addObject:"--follow"))
        (if options (arguments addObjectsFromArray:options))
        (arguments addObject:pattern)
        (@task setArguments:arguments)
        (@task setCurrentDirectoryPath:(@baseURL path))
        (set @stream (@task scheduledStreamWithStandardInput:nil))
        (@stream setDelegate:self))

    (- (void)filterResults:(id)sender is
        (let (filter (sender stringValue))
            (@arrayController setFilterPredicate:
                (if (filter length)
                    (NSPredicate predicateWithFormat:"groupName contains[cd] %@ or title contains[cd] %@"
                                       argumentArray:(`(,filter ,filter) array))
                    (else nil)))))

    (- (BOOL)filter:(id)command is ((self window) makeFirstResponder:@filterField))

    (- (void)gotoResultAndSplitVertically:(BOOL)vertical is
        (if (set mark ((@arrayController selectedObjects) lastObject))
            (set view ((current-window) splitVertically:vertical andOpen:(mark url)))
            ((view innerView) gotoLine:(mark line) column:(mark column))
            ((current-window) showWindow:nil)))

    (- (void)splitOpen:(id)sender is (self gotoResultAndSplitVertically:NO))
    (- (void)vsplitOpen:(id)sender is (self gotoResultAndSplitVertically:YES))

    (- (void)gotoResult:(id)sender is
        (if (set mark ((@arrayController selectedObjects) lastObject))
            ((current-window) gotoMark:mark)
            ((current-window) showWindow:nil)))
)

((ExMap defaultMap) define:"ack" syntax:"e" as:(do (cmd)
    (AckResultsController ackInURL:((current-explorer) rootURL) forPattern:(cmd arg))))

((ExMap defaultMap) define:"aa" syntax:"e" as:(do (cmd)
    (if (cmd arg)
        (set mark (((mark-manager stackWithName:"Ack Results") list) markAtIndex:((cmd arg) intValue)))
        (else (set mark (((mark-manager stackWithName:"Ack Results") list) current))))
    (if mark
        ((current-window) gotoMark:mark
        (else (cmd message:"No results"))))))

((ExMap defaultMap) define:'("anext" "an") syntax:"" as:(do (cmd)
    (if (set mark (((mark-manager stackWithName:"Ack Results") list) next))
        ((current-window) gotoMark:mark)
        (else (cmd message:"Already at the last result")))))

((ExMap defaultMap) define:'("anfile" "anf") syntax:"" as:(do (cmd)
    (set mark (((mark-manager stackWithName:"Ack Results") list) current))
    (set currentURL (mark url))
    (while (eq currentURL (mark url))
        (set mark (((mark-manager stackWithName:"Ack Results") list) next)))
    (if mark
        ((current-window) gotoMark:mark)
        (else (cmd message:"Already at the last result")))))

((ExMap defaultMap) define:'("apfile" "apf" "aNfile" "aNf") syntax:"" as:(do (cmd)
    (set mark (((mark-manager stackWithName:"Ack Results") list) current))
    (set currentURL (mark url))
    (while (eq currentURL (mark url))
        (set mark (((mark-manager stackWithName:"Ack Results") list) previous)))
    (if mark
        ((current-window) gotoMark:mark)
        (else (cmd message:"Already at the first result")))))

((ExMap defaultMap) define:'("aprevious" "ap" "aNext" "aN") syntax:"" as:(do (cmd)
    (if (set mark (((mark-manager stackWithName:"Ack Results") list) previous))
        ((current-window) gotoMark:mark)
        (else (cmd message:"Already at the first result")))))

((ExMap defaultMap) define:'("arewind" "afirst" "afir" "ar") syntax:"" as:(do (cmd)
    (if (set mark (((mark-manager stackWithName:"Ack Results") list) first))
        ((current-window) gotoMark:mark)
        (else (cmd message:"No results")))))

((ExMap defaultMap) define:'("alast" "ala") syntax:"" as:(do (cmd)
    (if (set mark (((mark-manager stackWithName:"Ack Results") list) last))
        ((current-window) gotoMark:mark)
        (else (cmd message:"No results")))))

((ViMap normalMap) map:"<cmd-F>" toExpression:(do ()
    (AckResultsController ackInURL:((current-explorer) rootURL) forPattern:nil)))

((ViMap explorerMap) map:"<cmd-F>" toExpression:(do ()
    (AckResultsController ackInURL:(((current-explorer) clickedFolderURLs) anyObject) forPattern:nil)))

; Add to main menu
(let (menu (((((NSApp mainMenu) itemWithTitle:"Edit") submenu) itemWithTitle:"Find") submenu))
    (menu addItem:(NSMenuItem separatorItem))
    ((menu addItemWithTitle:"Find in Project... (:ack<cr>)(:<c-u>ack<cr>)" action:nil keyEquivalent:"F") setTag:"4000")
    ((menu addItemWithTitle:"Go To Current Result (:aa<cr>)(:<c-u>aa<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Next Result (:anext<cr>)(:<c-u>anext<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Previous Result (:aprevious<cr>)(:<c-u>aprevious<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To First Result (:afirst<cr>)(:<c-u>afirst<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Last Result (:alast<cr>)(:<c-u>alast<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Next File (:anfile<cr>)(:<c-u>anfile<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Previous File (:apfile<cr>)(:<c-u>apfile<cr>)" action:nil keyEquivalent:"") setTag:"4000"))

