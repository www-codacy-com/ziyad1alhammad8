#import "RBObject+CocoaPods.h"
#import "CPPodfileReflection.h"
#import "CocoaPods-Swift.h"
#import "CPReflectionServiceProtocol.h"

#import <Fragaria/Fragaria.h>
#import <Fragaria/SMLSyntaxError.h>

#import "CPAppDelegate.h"

@interface CPPodfileReflection()

@property (weak) MGSFragariaView *editor;
@property (weak) CPPodfileEditorViewController *editorViewController;

@end

@implementation CPPodfileReflection

- (instancetype)initWithPodfileEditorVC:(CPPodfileEditorViewController *)editor fragariaEditor:(MGSFragariaView *)fragaria
{
  self = [super init];
  if (!self) { return nil; }

  _editor = fragaria;
  _editorViewController = editor;

  return self;
}

- (void)textDidChange:(NSNotification *)notification;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(parsePodfile) object:nil];
  if ([self shouldParseImmediately]) {
    [self performSelector:@selector(parsePodfile) withObject:nil afterDelay:0.01];
  } else {
    [self performSelector:@selector(parsePodfile) withObject:nil afterDelay:0.5];
  }
}

/// YES when the parsing should be updated immediately.
/// See https://github.com/CocoaPods/CocoaPods-app/issues/130
- (BOOL)shouldParseImmediately
{
  return self.editor.syntaxErrors.count > 0;
}

- (void)parsePodfile;
{
  CPUserProject *project = self.editorViewController.podfileViewController.userProject;

  NSXPCConnection *reflectionService = [(CPAppDelegate *)NSApp.delegate reflectionService];
  [reflectionService.remoteObjectProxy pluginsFromPodfile:project.contents
                                                withReply:^(NSArray<NSString *> * _Nullable plugins, NSError * _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (plugins) {
        project.podfilePlugins = plugins;
        // Clear any previous syntax errors.
        self.editor.syntaxErrors = nil;

      } else if ([error.userInfo[CPErrorName] isEqualToString:@"Pod::DSLError"]) {
        SMLSyntaxError *syntaxError = SyntaxErrorFromError(error);
        if (syntaxError) {
          self.editor.syntaxErrors = @[syntaxError];
        }

      } else {
        [[NSAlert alertWithError:error] beginSheetModalForWindow:self.editor.window
                                               completionHandler:nil];
      }
    });
  }];
}

static SMLSyntaxError * _Nullable
SyntaxErrorFromError(NSError * _Nonnull error)
{
  // A Pod::DSLError only wraps the real exception and provides nicer output in the CLI.
  // We want to retrieve information from the real exception.
  if ([error.userInfo[CPErrorName] isEqualToString:@"Pod::DSLError"]) {
    NSError *cause = error.userInfo[NSUnderlyingErrorKey];
    if (cause) {
      error = cause;
    }
  }

  NSString *description = error.localizedRecoverySuggestion;
  NSInteger lineNumber = -1;

  // A SyntaxError shows the line at which the error occurs in its message, not in its backtrace.
  if ([error.userInfo[CPErrorName] isEqualToString:@"SyntaxError"]) {
    // Example:
    //
    // Podfile:32: syntax error, unexpected tSTRING_BEG, expecting keyword_do or '{' or '('
    //  target 'Artsy' do
    //          ^
    // Podfile:32: syntax error, unexpected keyword_do, expecting end-of-input
    NSScanner *scanner = [NSScanner scannerWithString:description];
    // For some reason, this message is sometimes preceded by "Pod::DSLError\n"
    [scanner scanUpToString:@"Podfile" intoString:NULL];
    [scanner scanString:@"Podfile:" intoString:NULL];
    [scanner scanInteger:&lineNumber];
    [scanner scanString:@": " intoString:NULL];
    description = [description substringFromIndex:scanner.scanLocation];

  } else {
    NSString *location = [error.userInfo[CPErrorRubyBacktrace] firstObject];
    if ([location componentsSeparatedByString:@":"].count < 2) {
      // Without a colon from which to parse a line number, there is no point in showing an error in the UI.
      return nil;
    }
    lineNumber = [location componentsSeparatedByString:@":"][1].integerValue;
  }

  // Capitalize the message.
  NSString *firstCharacter = [[description substringToIndex:1] uppercaseString];
  description = [firstCharacter stringByAppendingString:[description substringFromIndex:1]];

  // Remove any raw instance description of a Podfile object
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"#<Pod::Podfile:0[xX][0-9a-fA-F]+>"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:nil];
  description = [regex stringByReplacingMatchesInString:description
                                                options:0
                                                  range:NSMakeRange(0, [description length])
                                           withTemplate:NSLocalizedString(@"PODFILE_WINDOW_PODFILE_SYNTAX_ERROR_REPLACE", nil)];

  return [SMLSyntaxError errorWithDescription:description
                                      ofLevel:kMGSErrorCategoryError
                                       atLine:lineNumber];
}

@end
