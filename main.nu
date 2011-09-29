; Copyright (c) 2011 Martin Hedenfalk <martin@vicoapp.com>
;
; Permission to use, copy, modify, and/or distribute this software for any
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
(ackmap setKey:"<cr>" toAction:"defaultOpen:")
(ackmap setKey:"s" toAction:"splitOpen:")
(ackmap setKey:"v" toAction:"vsplitOpen:")
(ackmap setKey:"t" toAction:"tabOpen:")
(ackmap setKey:"o" toAction:"switchOpen:")
(ackmap setKey:"<tab>" toAction:"focusNextKeyView:")
(ackmap setKey:"<esc>" toAction:"cancelSearch:")
(ackmap setKey:"/" toAction:"filter:")

(class AckTableView is NSTableView
    (ivar (id) keyManager)

    (- (void)awakeFromNib is
        (set @keyManager (ViKeyManager keyManagerWithTarget:self defaultMap:ackmap)))

    ; Pass key events to the key manager
    (- (void)keyDown:(id)event is (@keyManager keyDown:event))
    (- (BOOL)performKeyEquivalent:(id)event is
        (if (eq ((self window) firstResponder) self)
            (@keyManager performKeyEquivalent:event)
            (else NO)))
    (- (id)keyManager:(id)keyManager evaluateCommand:(id)command is
        (self performCommand:command))

    ; Use a lighter blue as selection color
    (- (void)highlightSelectionInClipRect:(NSRect)clipRect is
        (set rect (self rectOfRow:(self selectedRow)))
        (if (and (eq ((self window) firstResponder) self) ((self window) isKeyWindow))
            ((NSColor colorWithDeviceRed:(/ 0x9B 0xFF) green:(/ 0xD1 0xFF) blue:(/ 0xFB 0xFF) alpha:1) set)
            (else ((NSColor colorWithDeviceRed:(/ 0xCF 0xFF) green:(/ 0xD2 0xFF) blue:(/ 0xD9 0xFF) alpha:1) set)))
        ((NSBezierPath bezierPathWithRect:rect) fill))

    ; swiping changes the active result list
    (- (void)swipeWithEvent:(id)event is
	((@keyManager parser) reset)
	(if (gt (event deltaX) 0)
                ((self delegate) gotoOlderList)
            (else (if (lt (event deltaX) 0)
		((self delegate) gotoNewerList)))))

    (- (BOOL)focusNextKeyView:(id)command is ((self window) selectNextKeyView:self))
    (- (BOOL)focusDocument:(id)command is ((current-window) showWindow:nil)) )


(class AckResultsController is NSWindowController
    (ivar (id) tableView (id) arrayController (id) task (id) stream (id) baseURL (id) matchedFiles
          (id) initialPattern (id) spinner (id) searchPattern (id) searchOptions (id) taskStatus
          (BOOL) closeOnFinish (id) infoLabel (id) filterField (id) activeListButton
          (id) optIgnoreCase (id) optSmartCase (id) optUseRegexp (id) optMatchWords (id) optFollowSymlinks
          (id) markStack (id) highlightRegexp (id) highlightColor)

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
        ((self window) setTitle:"Find in Project: #{(@baseURL displayString)}"))

    (- (id)initWithBaseURL:(id)aURL pattern:(id)pattern is
        (set @baseURL aURL)
        (super initWithWindowNibPath:"#{bundlePath}/AckResults.nib" owner:self)
        (set @initialPattern pattern)
        (set @markStack (mark-manager stackWithName:"Ack Results"))
        (@markStack clear)
        ; yellowish background color for matched text highlight
        (set @highlightColor (NSColor colorWithDeviceRed:(/ 0xF9 0xFF) green:(/ 0xFF 0xFF) blue:(/ 0xB5 0xFF) alpha:1))
        ((self nextRunloop) showWindow:nil)
        self)

    (- (void)windowDidLoad is
        ((self window) setTitle:"Find in Project: #{(@baseURL displayString)}")
        (@infoLabel setStringValue:"")
        (@arrayController setObjectClass:(ViMark class))
        (@arrayController bind:"contentArray" toObject:@markStack withKeyPath:"list.marks" options:nil)
        (@arrayController bind:"selectionIndexes" toObject:@markStack withKeyPath:"list.selectionIndexes" options:nil)
        (@markStack addObserver:self forKeyPath:"list" options:0 context:nil)
        (self updateLists)
        (((@searchPattern cell) cancelButtonCell) setTarget:self)
        (((@searchPattern cell) cancelButtonCell) setAction:"cancel:")
        (@tableView setDelegate:self)
        (@tableView setDoubleAction:"defaultOpen:")
	(user-defaults registerDefaults:
            (NSDictionary dictionaryWithList:
                '("ackIgnoreCase" 1 "ackSmartCase" 0 "ackUseRegexp" 1 "ackMatchWords" 0 "ackFollowSymlinks" 1)))
        (@searchOptions setTokenizingCharacterSet:(NSCharacterSet whitespaceAndNewlineCharacterSet))
        (if @initialPattern (self searchPattern:@initialPattern withOptions:nil)))

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
        (set markArray (NSMutableArray array))
        ((string lines) each:(do (line)
            (set match (/^(.{1,256}):(\d+):(\d+):\s*(.+)$/ findInString:line))
            (if (eq (match count) 5)
                (set url (@baseURL URLWithRelativeString:(match groupAtIndex:1)))
                (@matchedFiles addObject:url)
                (set line ((match groupAtIndex:2) integerValue))
                (set column ((match groupAtIndex:3) integerValue))
                (set title (match groupAtIndex:4))
                (set mark (ViMark markWithURL:url name:nil title:title line:line column:column))
                (mark setRepresentedObject:(@highlightRegexp allMatchesInString:title))
                (markArray addObject:mark) )))
        ((@markStack list) addMarksFromArray:markArray)
        (self updateInfoLabel)
        ; abort if too many results
        (if (gt ((@markStack list) count) 5000)
            (set @taskStatus "Aborted")
            (@task terminate)))

    (- (void)updateInfoLabel is
        (set matchInfo "#{((@arrayController arrangedObjects) count)} matches in #{(@matchedFiles count)} files.")
        (if (eq @taskStatus "")
            (@infoLabel setStringValue:matchInfo)
            (else (@infoLabel setStringValue:"#{matchInfo} #{@taskStatus}."))))

    (- (void)finish is
        ; (NSLog "waiting for ack to exit...")
        (@task waitUntilExit)
        (@spinner stopAnimation:nil)
        (set status (@task terminationStatus))
        (if (and (ne status 0) (eq @taskStatus ""))
            (set @taskStatus "Failed"))
        (self updateInfoLabel)
        (@stream close)
        (set @task nil)
        (if @closeOnFinish (self close)))

    ; stream delegate method
    (- (void)stream:(id)stream handleEvent:(int)event is
        (case event
            (NSStreamEventHasBytesAvailable (self parse:(stream data)))
            (NSStreamEventHasSpaceAvailable (stream shutdownWrite))
            (NSStreamEventErrorOccurred (self finish))
            (NSStreamEventEndEncountered (self finish))))

    (- (void)cancel:(id)sender is
        (if (@task)
            (set @taskStatus "Cancelled")
            (@task terminate)
            (else (@searchPattern setStringValue:""))))

    (- (void)search:(id)sender is
        (if (gt ((@searchPattern stringValue) length) 0)
            (self searchPattern:(@searchPattern stringValue) withOptions:(@searchOptions objectValue))))

    (- (id)searchPattern:(id)pattern withOptions:(id)options is
        ; make a new mark list and remember the search pattern, options and base URL
        ((@markStack makeList) setUserParameter:
            (NSDictionary dictionaryWithList:`("pattern" ,pattern "options" ,options "baseURL" ,(@baseURL))))
        (set @matchedFiles (NSMutableSet set))
        (set @taskStatus "")
        (self updateInfoLabel)
        (@spinner startAnimation:nil)
        (@searchPattern setStringValue:pattern)

        (set @highlightRegexp (ViRegexp regexpWithString:
            (cond ((user-defaults boolForKey:"ackUseRegexp") pattern)
                  ((user-defaults boolForKey:"ackMatchWords") "\\b#{(ViRegexp escape:pattern)}\\b")
                  (else (ViRegexp escape:pattern)))
            options:
            (cond ((user-defaults boolForKey:"ackSmartCase") (if (pattern isLowercase) ViRegexpIgnoreCase (else 0)))
                  ((user-defaults boolForKey:"ackIgnoreCase") ViRegexpIgnoreCase)
                  (else 0))))

        (@filterField setStringValue:"")
        (self filterResults:@filterField)
        ((self window) makeFirstResponder:@tableView)
        ; launch Ack
        (set @task ((NSTask alloc) init))
        (@task setLaunchPath:"#{bundlePath}/ack")
        (set arguments (NSMutableArray arrayWithObject:"--flush"))
        (arguments addObject:"--column")
        (if (user-defaults boolForKey:"ackSmartCase") (arguments addObject:"--smart-case")
            (else (if (user-defaults boolForKey:"ackIgnoreCase") (arguments addObject:"--ignore-case"))))
        (if (user-defaults boolForKey:"ackMatchWords") (arguments addObject:"--word-regexp"))
        (unless (user-defaults boolForKey:"ackUseRegexp") (arguments addObject:"--literal"))
        (if (user-defaults boolForKey:"ackFollowSymlinks") (arguments addObject:"--follow"))
        (if options (arguments addObjectsFromArray:options))
        (arguments addObject:pattern)
        (@task setArguments:arguments)
        (@task setCurrentDirectoryPath:(@baseURL path))
        (set @stream (@task scheduledStreamWithStandardInput:nil))
        (@stream setDelegate:self))

    (- (void)changeList:(id)sender is
	(if (eq (sender selectedSegment) 0)
		(@markStack previous)
            (else
                (@markStack next))))
    (- (void)gotoOlderList is (@markStack previous))
    (- (void)gotoNewerList is (@markStack next))
    (- (void)updateLists is
        (@activeListButton setEnabled:(not (@markStack atBeginning)) forSegment:0)
        (@activeListButton setEnabled:(not (@markStack atEnd)) forSegment:1))
    (- (void)clearLists:(id)sender is (@markStack clear) (@infoLabel setStringValue:"Cleared."))

    (- (void)observeValueForKeyPath:(id)keyPath ofObject:(id)object change:(id)change context:(int)context is
        (if (eq object @markStack) ; current list has changed, update the UI
            (self updateLists)
            ; Restore search settings from the result list
            (if (set params ((@markStack list) userParameter))
                (@searchPattern setStringValue:(params objectForKey:"pattern"))
                (@searchOptions setObjectValue:(params objectForKey:"options"))
                (set @baseURL (params objectForKey:"baseURL"))
                ((self window) setTitle:"Find in Project: #{(@baseURL displayString)}"))))

    (- (void)filterResults:(id)sender is
        (let (filter (sender stringValue))
            (@arrayController setFilterPredicate:
                (if (filter length)
                    (NSPredicate predicateWithFormat:"groupName contains[cd] %@ or title contains[cd] %@"
                                       argumentArray:(`(,filter ,filter) array))
                    (else nil)))))

    (- (BOOL)filter:(id)command is ((self window) makeFirstResponder:@filterField))
    (- (BOOL)cancelSearch:(id)command is (if (@task isRunning) (self cancel:nil)))

    (- (BOOL)validateMenuItem:(id)item is
        ((item menu) setFont:(NSFont menuFontOfSize:12))
        (case (item tag)
            (1 (item setState:(user-defaults boolForKey:"ackIgnoreCase")))
            (2 (item setState:(user-defaults boolForKey:"ackSmartCase")))
            (3 (item setState:(user-defaults boolForKey:"ackUseRegexp")))
            (4 (item setState:(user-defaults boolForKey:"ackMatchWords")))
            (5 (item setState:(user-defaults boolForKey:"ackFollowSymlinks")))
            (else (item setState:0)))
        (case (item tag)
            (2 (user-defaults boolForKey:"ackIgnoreCase")) ; no smart case unless ignore case
            (else YES)))

    (- (BOOL)toggleOption:(id)opt is
        (let (value (not (user-defaults boolForKey:opt)))
            (user-defaults setBool:value forKey:opt)
            value))
    (- (void)toggleIgnoreCase:(id)sender is (self toggleOption:"ackIgnoreCase"))
    (- (void)toggleSmartCase:(id)sender is (self toggleOption:"ackSmartCase"))
    (- (void)toggleUseRegexp:(id)sender is
        (if (self toggleOption:"ackUseRegexp")
            (user-defaults setBool:NO forKey:"ackMatchWords")))
    (- (void)toggleMatchWords:(id)sender is
        (if (self toggleOption:"ackMatchWords")
            (user-defaults setBool:NO forKey:"ackUseRegexp")))
    (- (void)toggleFollowSymlinks:(id)sender is (self toggleOption:"ackFollowSymlinks"))

    (- (void)openInPosition:(int)position is
        (if (set mark ((@arrayController selectedObjects) lastObject))
            ((current-window) gotoMark:mark positioned:position)
            ((current-window) showWindow:nil)))
    (- (void)splitOpen:(id)sender is (self openInPosition:ViViewPositionSplitAbove))
    (- (void)vsplitOpen:(id)sender is (self openInPosition:ViViewPositionSplitLeft))
    (- (void)tabOpen:(id)sender is (self openInPosition:ViViewPositionTab))
    (- (void)switchOpen:(id)sender is (self openInPosition:ViViewPositionReplace))
    (- (void)defaultOpen:(id)sender is (self openInPosition:ViViewPositionDefault))

    (- (void)tableView:(id)aTableView willDisplayCell:(id)aCell forTableColumn:(id)aTableColumn row:(int)rowIndex is
        (set mark ((@arrayController arrangedObjects) objectAtIndex:rowIndex))
        (set t (mark title))
        (set u "#{((mark url) displayString)} line #{(mark line)}")
        (set s ((NSMutableAttributedString alloc) initWithString:"#{t}\n#{u}"))
        (s addAttribute:NSFontAttributeName value:(NSFont userFixedPitchFontOfSize:12) range:`(0 ,(t length)))
        (s addAttribute:NSFontAttributeName value:(NSFont systemFontOfSize:12) range:`(,(+ (t length) 1) ,(u length)))
        (s addAttribute:NSForegroundColorAttributeName value:(NSColor grayColor) range:`(,(+ (t length) 1) ,(u length)))
        (set ps ((NSParagraphStyle defaultParagraphStyle) mutableCopy))
        (ps setLineBreakMode:NSLineBreakByTruncatingTail)
        (s addAttribute:NSParagraphStyleAttributeName value:ps range:`(0 ,(s length)))
        ((mark representedObject) each:(do (m)
            (s addAttribute:NSBackgroundColorAttributeName value:@highlightColor range:(m rangeOfMatchedString))))
        (aCell setStringValue:s)
        (aCell setImage:((NSWorkspace sharedWorkspace) iconForFile:((mark url) path))))
)


; Map ex commands to control the search results

((ExMap defaultMap) define:"ack" syntax:"e" as:(do (cmd)
    (AckResultsController ackInURL:((current-explorer) rootURL) forPattern:(cmd arg))))

((ExMap defaultMap) define:"aa" syntax:"e" as:(do (cmd)
    (if (cmd arg)
        (set mark (((mark-manager stackWithName:"Ack Results") list) markAtIndex:((cmd arg) intValue)))
        (else (set mark (((mark-manager stackWithName:"Ack Results") list) current))))
    (if mark
        ((current-window) gotoMark:mark)
        (else (cmd message:"No results")))))

((ExMap defaultMap) define:'("anext" "an") syntax:"" as:(do (cmd)
    (if (set mark (((mark-manager stackWithName:"Ack Results") list) next))
        ((current-window) gotoMark:mark)
        (else (cmd message:"Already at the last result")))))

((ExMap defaultMap) define:'("anfile" "anf") syntax:"" as:(do (cmd)
    (let (list ((mark-manager stackWithName:"Ack Results") list))
        (set mark (list current))
        (set currentURL (mark url))
        (while (eq currentURL (mark url))
            (set mark (list next)))
        (if mark
            ((current-window) gotoMark:mark)
            (else (cmd message:"Already at the last result"))))))

((ExMap defaultMap) define:'("apfile" "apf" "aNfile" "aNf") syntax:"" as:(do (cmd)
    (let (list ((mark-manager stackWithName:"Ack Results") list))
        (set mark (list current))
        (set currentURL (mark url))
        (while (eq currentURL (mark url))
            (set mark (list previous)))
        (if mark
            ((current-window) gotoMark:mark)
            (else (cmd message:"Already at the first result"))))))

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

((ExMap defaultMap) define:'("aolder" "aol") syntax:"" as:(do (cmd)
    (let (stack (mark-manager stackWithName:"Ack Results"))
        (if (stack atBeginning)
            (cmd message:"Already at oldest results")
            (else (stack previous))))))

((ExMap defaultMap) define:'("anewer" "anew") syntax:"" as:(do (cmd)
    (let (stack (mark-manager stackWithName:"Ack Results"))
        (if (stack atEnd)
            (cmd message:"Already at newest results")
            (else (stack next))))))

; Pressing <cmd-F> bring up the search window
((ViMap normalMap) map:"<cmd-F>" toExpression:(do ()
    (AckResultsController ackInURL:((current-explorer) rootURL) forPattern:nil)))

; Pressing <cmd-F> in the file explorer sets the search folder to the selected folder
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
    ((menu addItemWithTitle:"Go To Previous File (:apfile<cr>)(:<c-u>apfile<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Older Results (:aolder<cr>)(:<c-u>aolder<cr>)" action:nil keyEquivalent:"") setTag:"4000")
    ((menu addItemWithTitle:"Go To Newer Results (:anewer<cr>)(:<c-u>anewer<cr>)" action:nil keyEquivalent:"") setTag:"4000"))

