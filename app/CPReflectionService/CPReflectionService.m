#import "CPReflectionService.h"
#import "RBObject+CocoaPods.h"
#import "NSArray+Helpers.h"

@implementation CPReflectionService

- (void)pluginsFromPodfile:(NSString * _Nonnull)contents
                 withReply:(void (^ _Nonnull)(NSArray<NSString *> * _Nullable plugins, NSError * _Nullable error))reply;
{
  [RBObject performBlock:^{
    // Use just `Podfile` as the path so that we can make assumptions about error messages
    // and easily remove the path being mentioned.
    RBPathname *pathname = [RBObjectFromString(@"Pathname") new:@"Podfile"];

    RBPodfile *podfile = [RBObjectFromString(@"Pod::Podfile") from_ruby:pathname :contents];
    NSArray *plugins = podfile.plugins.allKeys;
    reply(plugins, nil);

  } error:^(NSError * _Nonnull error) {
    reply(nil, error);
  }];
}

- (void)installedPlugins:(void (^ _Nonnull)(NSArray<NSString *> * _Nullable plugins, NSError * _Nullable error))reply;
{
  [RBObject performBlock:^{
    RBPluginManager *pluginManager = RBObjectFromString(@"CLAide::Command::PluginManager");
    NSArray *specs = [pluginManager installed_specifications_for_prefix:@"cocoapods"];

    reply([specs map:^id(id spec) {
      return [spec name];
    }], nil);

  } error:^(NSError * _Nonnull error) {
    reply(nil, error);
  }];
}

- (void)XcodeIntegrationInformationFromPodfile:(NSString * _Nonnull)contents
                              installationRoot:(NSString * _Nonnull)installationRoot
                                     withReply:(void (^ _Nonnull)(NSDictionary * _Nullable information, NSError * _Nullable error))reply;
{
  [RBObject performBlock:^{
    RBPathname *pathname = [RBObjectFromString(@"Pathname") new:@"Podfile"];
    RBPodfile *podfile = [RBObjectFromString(@"Pod::Podfile") from_ruby:pathname :contents];
    NSDictionary *info = [RBObjectFromString(@"Pod::App") analyze_podfile:podfile :[RBObjectFromString(@"Pathname") new:installationRoot]];
    reply(info, nil);

  } error:^(NSError * _Nonnull error) {
    reply(nil, error);
  }];

}

- (void)allPods:(void (^ _Nonnull)(NSArray<NSString *> * _Nullable pods, NSError * _Nullable error))reply
{
  [RBObject performBlock:^{
    reply([RBObjectFromString(@"Pod::App") all_pods], nil);
  } error:^(NSError * _Nonnull error) {
    reply(nil, error);
  }];
}

- (void)noMethodError:(void (^)(NSError * _Nullable))reply;
{
  [RBObject performBlock:^{
    [RBObjectFromString(@"Pod::App") no_method];
    reply(nil);
  } error:^(NSError * _Nonnull error) {
    reply(error);
  }];
}

@end
