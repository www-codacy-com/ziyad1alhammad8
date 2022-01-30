import Cocoa
import Fragaria

/// The Editor's role is to show our Fragaria editor
/// and ensure the changes are sent back upstream to the 
/// CPPodfileViewController's CPUserProject

class CPPodfileEditorViewController: NSViewController, NSTextViewDelegate, SMLAutoCompleteDelegate {

  @IBOutlet var editor: MGSFragariaView!
  var syntaxChecker: CPPodfileReflection!
  let commentSyntax = "# "
  let indentationSyntax = "  "
  var autoCompletions: [String] = {
    if let path = NSBundle.mainBundle().pathForResource("Podfile", ofType: "plist"),
      dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
      words = dict["autocompleteWords"] as? [String] {
        return words
    }
    return []
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    let appDelegate = NSApp.delegate as? CPAppDelegate
    appDelegate?.reflectionService.remoteObjectProxy.allPods { (pods, error) in
      if let pods = pods {
        self.autoCompletions.appendContentsOf(pods)
      }
    }
  }

  // As the userProject is DI'd into the PodfileVC
  // it occurs after the view is set up.

  override func viewWillAppear() {
    super.viewWillAppear()

    guard let podfileVC = podfileViewController, project = podfileVC.userProject else {
      return print("CPPodfileEditorViewController is not set up with a PodfileVC in the VC heirarchy.")
    }
    
    project.delegate = self

    editor.syntaxColoured = true
    editor.syntaxDefinitionName = "Podfile"
    editor.string = project.contents

    let settings = CPFontAndColourGateKeeper()
    editor.textFont = settings.defaultFont
    editor.colourForNumbers = settings.cpGreen
    editor.colourForStrings = settings.cpRed
    editor.colourForComments = settings.cpBrightBrown
    editor.colourForKeywords = settings.cpBlue
    editor.colourForVariables = settings.cpGreen
    editor.colourForInstructions = settings.cpBrightMagenta
    editor.autoCompleteDelegate = self

    editor.tabWidth = 2
    editor.indentWithSpaces = true
    
    project.undoManager = editor.textView.undoManager
    
    syntaxChecker = CPPodfileReflection(podfileEditorVC: self, fragariaEditor: editor)
    syntaxChecker.textDidChange(NSNotification(name: "", object: nil))
  }

  func completions() -> [AnyObject]! {
      return autoCompletions
  }

  func textDidChange(notification: NSNotification) {
    guard let textView = notification.object as? NSTextView,
      let podfileVC = podfileViewController else { return }

    podfileVC.userProject.contents = textView.string ?? ""

    // Passing the message on to the syntax checker
    syntaxChecker.textDidChange(notification)
  }

  @IBAction func commentSelection(sender: NSMenuItem) {
    let selection = selectedLines(editor.textView)
    let change = commentsInSelection(selection) ? removeCommentsFromLines : addCommentsInLines
    let range = applyTextChange(change, toSelection: selection)
    editor.textView.setSelectedRange(NSMakeRange(range.location + range.length, 0))
  }

  @IBAction func indentSelection(sender: NSMenuItem) {
    let range = applyTextChange(indentedSelection, toSelection: selectedLines(editor.textView))
    editor.textView.setSelectedRange(range)
  }

  @IBAction func outdentSelection(sender: NSMenuItem) {
    let range = applyTextChange(outdentedSelection, toSelection: selectedLines(editor.textView))
    editor.textView.setSelectedRange(range)
  }
  
  @IBAction func increaseFontSize(sender: NSMenuItem) {
    let settings = CPFontAndColourGateKeeper()
    settings.increaseDefaultFontSize()
    editor.textFont = settings.defaultFont
  }
  
  @IBAction func decreaseFontSize(sender: NSMenuItem) {
    let settings = CPFontAndColourGateKeeper()
    settings.decreaseDefaultFontSize()
    editor.textFont = settings.defaultFont
  }

  /// Apply a text transformation to a selection
  ///
  /// The transformation is provided as a closure. Returns an NSRange with the new selection, maintaining selected
  /// the string selected by the user.
  /// - parameter change: the closure that accepts `[String]` and returns `[String]`
  /// - parameter selection: an array of Strings representing the lines of the selection
  /// - returns: NSRange

  func applyTextChange(change: ([String] -> [String]), toSelection selection: [String]) -> NSRange {
    let startingSelection = editor.textView.selectedRange()
    let linesSelection = selectedLinesRange(editor.textView)
    let processed = change(selection)
    let newText = "\(processed.joinWithSeparator("\n"))\n"

    editor.textView.setSelectedRange(linesSelection)
    editor.textView.insertText(newText)

    // Restore the user's selection by calculating how the text moved
    let charDifference = linesSelection.length - newText.characters.count

    // Figure out how the first line (the starting location of the selection) moved
    let firstLineChange = ((processed.first?.characters.count ?? 0) - (selection.first?.characters.count ?? 0))

    // Return the new selection. Comparing the starting point with the absolute location of the first line 
    // prevents the cursor from skipping back to the line above
    return NSMakeRange(max(linesSelection.location, startingSelection.location + firstLineChange),
      startingSelection.length - charDifference - firstLineChange)
  }

}

/// Implements methods to indent the Podfile

typealias Indentation = CPPodfileEditorViewController
extension Indentation {

  /// Indents the selected text
  ///
  /// Adds two white spaces at the start of each line
  /// - parameter lines: an array of strings representing the user's selection
  /// - returns: [String]

  func indentedSelection(selection: [String]) -> [String] {
    return selection.map { line in
      return line.stringByReplacingCharactersInRange(Range(start: line.startIndex, end: line.startIndex), withString: indentationSyntax)
    }
  }

  /// Outdents the current selection
  ///
  /// Removes either a single tab or a single string formed by one or two white spaces from the start of the lines
  /// - parameter lines: an array of strings representing the user's selection
  /// - returns: [String]

  func outdentedSelection(selection: [String]) -> [String] {
    let indent = try! NSRegularExpression(pattern: "^\t|^\\s{1,2}", options: .CaseInsensitive)
    return selection.map { line in
      let firstMatch = indent.rangeOfFirstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.characters.count))
      return firstMatch.location != NSNotFound ? (line as NSString).stringByReplacingCharactersInRange(firstMatch, withString: "") : line
    }
  }

}

/// Implements methods to toggle comments in the Podfile

typealias Commenting = CPPodfileEditorViewController
extension Commenting {

  /// Checks wether the selection consists of solely comments
  /// - parameter selection: an array of strings representing the user's selection
  /// - returns: Bool

  func commentsInSelection(selection: [String]) -> Bool {
    let regex = try! NSRegularExpression(pattern: "\\s*#\\s*", options: .CaseInsensitive)

    return selection.reduce(true) { (all, line) -> Bool in
      return regex.matchesInString(line, options: .Anchored, range: NSMakeRange(0, line.characters.count)).count > 0 && all
    }
  }

  /// Removes the comment syntax from the selection. 
  ///
  /// Removes '# ' and '#' occurences from the start of the lines
  /// - parameter lines: an array of strings representing the user's selection
  /// - returns: [String]

  func removeCommentsFromLines(lines: [String]) -> [String] {
    let comment = try! NSRegularExpression(pattern: "#\\s?", options: .CaseInsensitive)
    return lines.map { line in
      let firstMatch = comment.rangeOfFirstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.characters.count))
      return (line as NSString).stringByReplacingCharactersInRange(firstMatch, withString: "")
    }
  }

  /// Adds the comment syntax to the selected text
  ///
  /// Adds '# ' at the start of each line
  /// - parameter lines: an array of strings representing the user's selection
  /// - returns: [String]

  func addCommentsInLines(lines: [String]) -> [String] {
    return lines.map { line in
      return line.stringByReplacingCharactersInRange(Range(start: line.startIndex, end: line.startIndex), withString: commentSyntax)
    }
  }

}

/// Implements methods to retrieve the selected lines of text from a NSTextView

typealias EditorLineSelection = CPPodfileEditorViewController
extension EditorLineSelection {

  /// Returns the selected lines of text as an array of strings
  ///
  /// - parameter textView: the `NSTextView` containing the selection
  /// - returns: [String]

  func selectedLines(textView: NSTextView) -> [String] {
    guard let selection = selectedLinesText(textView) where selection.characters.count > 0 else { return [] }

    // The substring is required to filter out the empty last line returned otherwise
    return selection.substringToIndex(selection.endIndex.predecessor()).componentsSeparatedByString("\n")
  }

  /// Returns the text for the selected lines. It includes partially selected lines of text.
  ///
  /// - parameter textView: the `NSTextView` containing the selection
  /// - returns: String?

  func selectedLinesText(textView: NSTextView) -> String? {
    guard let text = textView.string else { return .None }

    return (text as NSString).substringWithRange(selectedLinesRange(textView))
  }

  /// Returns the selected text's range
  ///
  /// - parameter textView: the `NSTextView` containing the selection
  /// - returns: NSRange

  func selectedLinesRange(textView: NSTextView) -> NSRange {
    guard let text = textView.string else { return NSMakeRange(0, 0) }

    return (text as NSString).lineRangeForRange(editor.textView.selectedRange())
  }

}

// MARK: - CPUserProjectDelegate
extension CPPodfileEditorViewController: CPUserProjectDelegate {
  
  func contentDidChangeinUserProject(userProject: CPUserProject) {
    editor.string = userProject.contents
    
    // Passing the message on to the syntax checker
    syntaxChecker.textDidChange(NSNotification(name: "", object: nil))
  }
}
