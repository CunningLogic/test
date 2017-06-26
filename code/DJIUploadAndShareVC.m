//
//  DJIUploadAndShareVC.m
//  Phantom3
//
//  Created by pygzx on 15/8/24.
//  Copyright (c) 2015年 DJIDevelopers.com. All rights reserved.
//

#import "DJIUploadAndShareVC1.h"
#import "UIImage+ImageEffects2.h"
#import "UploadManager3.h"
#import "DJIProgressButton.h"
#import "SkinViewController+Com.h"
#import "PlaceHolderTextView.h"
#import "DJIShareCenterView.h"
#import "UploadFile.h"
#import "UIView+action.h"
#import "UploadTagSelectVC.h"
#import "DefaultOrientationNC.h"
#import "SettingManager.h"
#import "ShareInstance.h"
#import "ShareManager.h"
#import "DBVideo.h"
#import "DBPhoto.h"
#import "SocialMediaSelectView.h"
#import "UIView+Loading.h"
#import "MainViewController.h"
#import "UserManager.h"
#import "MineVC.h"
#import "ExploreVC.h"
#import "DJIIdleTimerManager.h"
#import <Social/Social.h>
#import "ComHelper.h"
#import "VideoPreviewVC.h"
#import "DJIMakeMovieVC.h"
#import "DJIMakeMovieLiteVC.h"
#import "DJIExploreDisplayImageVC.h"
#import "DJIPulishArtWorkProgressView.h"
#import "SkinViewController+Share.h"
#import "DJIShareMoreVC.h"
#import "DJIShareFinishVC.h"
#import "DJIDispatchTool.h"
#import "DJIVideoEditProject.h"
#import "UIButton+ButtonHitArea.h"
#import "DJIVideoProjectManager.h"
#import "DJISelectCoverVC.h"
#import "UIView+Tips.h"
#import "DJIPreviewVC.h"
#import "ALAssetsLibrary+Custom.h"
#import <MagicalRecord/MagicalRecord.h>
#import "DJIStyleAlertView.h"
#import "DJIStyleAlertView+videoEditor.h"
#import "DJIMediaTransferTool.h"
#import "DJIShareProtocolManager.h"
#import "DJILayoutPreviewVC.h"
#import "DJIMakeMovieMusicManager.h"
#import "CFileHelper.h"
#import "Reachability.h"
#import "DJIAnalyticsAbstract.h"
#import "RRBundleRedirect.h"
#import "DJIReachability.h"

#define Last_Share_Social_Media_Key @"Last_Share_Social_Media_Key"

static BOOL bUploadLock = NO;   //保证 同时只有一个 上传任务在执行（包括 freeeye 或 视频/图片 分享）
static UIBackgroundTaskIdentifier      bgUploadIdentifier;  //后台上传 任务id

static NSString *shareProductClass = nil;   //

@interface UploadAndSharePresentingAnimator : NSObject<UIViewControllerAnimatedTransitioning>

@property (nonatomic, strong)       UIViewController    *sourceVC;

@end

@implementation UploadAndSharePresentingAnimator


- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext
{
    return 0.3;
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext {
    //    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UINavigationController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    MainViewController    *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    DJIUploadAndShareVC *sourceVC = (DJIUploadAndShareVC*)self.sourceVC;

    //获取到动画的源 imageView和 起始frame
    CGRect startFrame = sourceVC.presentFromRect;
    UIView *fromView = sourceVC.presentFromView;
    CGRect toFrame = sourceVC.presentToRect;

    //图片动画
    fromView.frame = startFrame;
    toViewController.view.frame = [UIScreen mainScreen].bounds;
    toViewController.view.alpha = 0;
    [transitionContext.containerView addSubview:toViewController.view];
    [transitionContext.containerView addSubview:fromView];
    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 options:UIViewAnimationOptionAllowAnimatedContent animations:^{
        toViewController.view.alpha = 0.3;
        fromVC.view.alpha = 0.3;
        fromView.frame = toFrame;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            toViewController.view.alpha = 1;
            fromVC.view.alpha = 0;
        } completion:^(BOOL finished) {
            [fromView removeFromSuperview];
            fromVC.view.alpha = 1;
            [transitionContext completeTransition:YES];
        }];
    }];
}

@end

typedef NS_OPTIONS(NSUInteger, MediaShareSource) {
    MediaShareSource_Media       = 0,  //普通的 视频，图片文件分享， 数据源是 UploadFile
    MediaShareSource_Frames       = 1,  //序列帧， 数据源是 一系列的本地图片
};

@interface DJIUploadAndShareVC () <
UploadTagSelectVCDelegate,
DJIPulishArtWorkProgressViewDelegate,
DJIShareCenterViewDelegate,
UITextViewDelegate,
UIViewControllerTransitioningDelegate, UIDocumentInteractionControllerDelegate> {
    NSMutableDictionary <NSNumber*, NSNumber*>  *_frameProgressDic;   //key为 上传task id，value为 对应的task 的progress（0-1）
    
    BOOL    _useStaticProductClass;
}

@property (nonatomic, strong) UIImageView* imageView;
@property (nonatomic, strong) UIButton* playButton;
@property (nonatomic, strong) UIButton* coverButton;
@property (nonatomic, strong) PlaceHolderTextView* titleField;
//@property (nonatomic, strong) PlaceHolderTextView* descView;
@property (nonatomic, strong) UIScrollView* tagsView;
@property (nonatomic, strong) UITapGestureRecognizer* tagsViewTapRec;
@property (nonatomic, strong) UILabel* networkErrorView;
@property (nonatomic, strong) DJIShareCenterView* shareCenterView;
@property (nonatomic, strong) DJIPulishArtWorkProgressView* progressView;
@property (nonatomic, strong) UILabel* tipsLabel;

@property (nonatomic, strong) NSArray* tagsArray;

@property (nonatomic, strong) NSTimer* progressTimer;
@property (nonatomic, assign) CGFloat fakeProgress;
@property (nonatomic, assign) BOOL shouldJumpToProfile;
@property (nonatomic, assign) BOOL isUploading;
@property (nonatomic, strong) DJIReachability *reachability;

@property (nonatomic, strong) UIButton* btnShare;

@property (nonatomic, strong) ShareInstance* shareInstance;
@property (nonatomic, strong) UIDocumentInteractionController* documentController;

//部分业务数据
@property (nonatomic, strong) DJIVideoEditProject* videoProject;
@property (nonatomic, strong) UploadFile* uploadFile;
@property (nonatomic, strong) VEUploader* uploader;
//序列帧分享模式
@property (nonatomic, copy) NSString* framesPathPrefix;
@property (nonatomic, copy) NSString* framesFileSuffix;
@property (nonatomic, assign) NSInteger framesImageCount;
@property (nonatomic, strong) DJIMakeMovieMusic *framesBgm;
@property (nonatomic, copy) NSString* segmentId;
@property (nonatomic, strong) NSArray<DJIMediaUploadTask*>* frameUploadTasks;


@property (nonatomic, assign) MediaShareSource shareSource;
@property (nonatomic, strong) DJISelectCoverVC* coverVC;

@end

@implementation DJIUploadAndShareVC
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source
{
    UploadAndSharePresentingAnimator *animator = [UploadAndSharePresentingAnimator new];
    animator.sourceVC = self;
    return animator;
}

- (instancetype)initWithFile:(UploadFile *)file {
    if (self = [super init]) {
        self.uploadFile = file;
        file.shouldReserveFile = YES;
    }

    return self;
}

- (id) initWithFileAndProductClass:(UploadFile*)file {
    if (self = [self initWithFile:file])  {
        _useStaticProductClass = YES;
    }
    return self;
}

- (id) initWithFile:(UploadFile*)file withVideoProject: (DJIVideoEditProject*)project {
    if (self = [super init]) {
        self.uploadFile = file;
        file.shouldReserveFile = YES;
        self.videoProject = project;
        //区分自动编辑和 旅行漫记
        if (project.isLightEdit) {
            if (project.lightEditDescription.length == 36) {   //自动编辑
                file.shareSource = 4;
            }
            else {
                file.shareSource = 3;   //旅行漫记
            }
        }
    }

    return self;
}




- (id) initWithImageFrames:(NSString*)pathPrefix suffix:(NSString*)suffix imageCount:(NSInteger)imageCount musicId:(NSInteger)musicId
                 segmentId:(NSString*)segmentId{
    if (self = [super init]) {
        self.framesPathPrefix = pathPrefix;
        self.framesFileSuffix = suffix;
        self.framesImageCount = imageCount;
        self.shareSource = MediaShareSource_Frames;
        DJIMakeMovieMusic* music = [[DJIMakeMovieMusicManager sharedInstance] getMusicWithMusicId:musicId];
        self.framesBgm = music;
        self.segmentId = segmentId?:@"undefined";
        _frameProgressDic = [NSMutableDictionary dictionaryWithCapacity:imageCount];
        //序列帧分享缓存
        //只保存 去除 序列帧文件夹部分的 UUID。 避免下次沙盒绝对路径变化导致文件读不到
        NSString *prefixStripWorkPath = [pathPrefix stringByReplacingOccurrencesOfString:[CFileHelper getWorksPath] withString:@""];
        [ShareManager saveFrameShareCache:@{FrameShareKey_PathPrefix:prefixStripWorkPath?:@"",
                                            FrameShareKey_Suffix:suffix?:@"",
                                            FrameShareKey_ImageCount:@(imageCount),
                                            FrameShareKey_MusicId:@(musicId)} key:segmentId];
    }

    return self;
}

+ (void)setShareProductClass:(NSString*)productClass {
    shareProductClass  = productClass;
}

- (void)dealloc {
    [self.reachability stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver: self name: UIApplicationWillEnterForegroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self name: kDJIReachabilityChangedNotification object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self name: kTwitterShareFailureNofication object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self invalidateTimer];
}

- (UIColor *)backgroundColor {
    return [UIColor whiteColor];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidLoad {
    [super viewDidLoad1];
    //    self.title = NSLocalizedString(@"share", nil);
    UIView* leftView;
    if (self.videoProject || (!self.uploadFile.isPhoto && self.fromMakeMovieVC == YES)) {
       /* UIButton* button = [self createHeaderTextBtn: NSLocalizedString(@"library_share_edit", nil)];
        [button setTitleColor: UIColorFromRGB(0x1C8CEF) forState: UIControlStateNormal];
        [button addTarget: self action: @selector(OnBack:) forControlEvents: UIControlEventTouchUpInside];
        leftView = button;*/
        leftView = [self createBackBtn];
    }
    else {
        UIButton* button = (UIButton*)[self createBackBtn];
        [button addTarget:self action:@selector(OnOnlyBack:) forControlEvents:UIControlEventTouchUpInside];
        leftView = button;
    }

    if (self.shareSource == MediaShareSource_Frames) {
        self.title = NSLocalizedString(@"library_share_post", @"序列帧 发布界面 标题 | 发布");
    }
    [self createHeaderWithBg: YES LeftView: leftView HeaderText: YES RightView: [self createShareButton]];

    self.navTitleLabel.textColor = UIColorFromRGB(0x494949);
    self.pageHeaderView.backgroundColor = [UIColor clearColor];

    [self buildImageView];
    if (!self.uploadFile.isPhoto && self.shareSource == MediaShareSource_Media) {   //分享视频  有设置封面入口 和播放功能
        [self buildPlayButton];
        [self buildCoverButton];
    }
    [self buildShareContent];   //分享内容，包括title， 标签等

    [self buildShareCenterView];

    [self setupRandomText];
    NSString* title = [self getShareContent:@"title"];
    if (title) {
        self.titleField.placeHolder = title;
    }


    self.reachability = [DJIReachability reachabilityForInternetConnection];
    [self.reachability startNotifier];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appWillEnterForeGround:) name: UIApplicationWillEnterForegroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(reachabilityDidChange:) name: kDJIReachabilityChangedNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(twitterShareComplete:) name: kTwitterShareFailureNofication object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(shareSuccess:) name: kShareSuccessNotification object: nil];
    //这里主要是为了 防止 上传时，关掉 shareVC，然后再次打开shareVC后， finishBlock里的 weakSelf 还是上次的那个（也就是nil），导致 完成后无法响应相关操作
    [NOTIFY_CENTER addObserver:self selector:@selector(onShareUploadSuccess:) name:DJIGO_Notification_ShareUploadSuccess object:nil];
    [NOTIFY_CENTER addObserver:self selector:@selector(onShareUploadFailed:) name:DJIGO_Notification_ShareUploadFailed object:nil];

    //先存本地。 存储失败，隐藏instgram 分享
    if (self.uploadFile) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc]init];
            if (self.uploadFile.isPhoto) {
                [assetsLibrary writeImageDataToSavedPhotosAlbum:[NSData dataWithContentsOfURL:self.uploadFile.url] metadata:nil completionBlock:^(NSURL *assetURL, NSError *error) {
                    self.uploadFile.mediaData.assetURLString = assetURL.absoluteString;
                    if (error) {
                        dispatch_run_on_sync_main(^{
                            [self.shareCenterView hideInstgram:YES];
                        });

                    }
                }];
            }
            else {
                BOOL shouldSaveToAlbum = NO;
                if (!self.assetUrl) {
                    shouldSaveToAlbum = YES;
                }
                else if (![PHAsset fetchAssetsWithALAssetURLs:@[[NSURL URLWithString:self.assetUrl]] options:nil].firstObject) {
                    shouldSaveToAlbum = YES;
                    [ShareManager removeAssetUrlOfSource:self.uploadFile.url.path.lastPathComponent]; //如果相册里的asset被删了，则移除对应的记录
                }
                //如果是quickMovie，不再存 相册， 之前存过了
                if ([self.uploadFile.currentItem isKindOfClass:[CSegment class]] && ((CSegment *)self.uploadFile.currentItem).isQuickMovie) {
                    shouldSaveToAlbum = NO;
                }
                if (shouldSaveToAlbum) {
                    ALAssetsLibrary *library = [ALAssetsLibrary sharedLibrary];
                    [library saveVideo:self.uploadFile.url toAlbum:@"DJI Works" completion:^(NSURL *assetURL, NSError *error) {
                        if (error) {
                            return;
                        }
                        self.uploadFile.mediaData.assetURLString = assetURL.absoluteString;
                        [ShareManager saveAssetUrlWithSourceUrl:self.uploadFile.url.path.lastPathComponent assetUrl:assetURL.absoluteString];
                        [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
                    } failure:^(NSError *error) {
                    }];
                }
                else {  //上级界面已经保存过了，不用再存相册
                    self.uploadFile.mediaData.assetURLString = self.assetUrl;
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
                }
            }
        });
    }


}

- (BOOL)prefersStatusBarHidden {
    if (self.fromFPV) return YES;   //fpv 横屏模式，不显示statusbar
    return NO;
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    //自动上传
    if (!self.isUploading && self.autoUpload) {

        if (self.shareSource == MediaShareSource_Frames) {
            [self OnFramesPost:nil];
        } else {
            [self OnShare:nil];
        }
    }


}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear: animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;

}

#pragma mark - Rotate

-(int)headerHeight
{
    //
    if ([self prefersStatusBarHidden]) {
        return 44;
    }
    return 44+20;//哭
}

-(BOOL) shouldAutorotate{
    return YES;
}


- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IS_IPAD) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        if ((self.fromFPV && !IS_IPAD) || !ORIRENTATION_IS_PORTRAIT) {
            return UIInterfaceOrientationMaskLandscape;
        }
        return UIInterfaceOrientationMaskPortrait;
    }
}


- (UIInterfaceOrientation) preferredInterfaceOrientationForPresentation {
    if (self.orientationOfFPV == UIInterfaceOrientationLandscapeRight ||
        self.orientationOfFPV == UIInterfaceOrientationLandscapeLeft) {
        return self.orientationOfFPV;
    }
    else if (self.supportedInterfaceOrientations == UIInterfaceOrientationMaskLandscape) {
        return [[UIApplication sharedApplication] statusBarOrientation];
    }
    return [super preferredInterfaceOrientationForPresentation];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self setNeedsStatusBarAppearanceUpdate];

}


#pragma mark - public
- (void)updateCoverWithImage:(UIImage*)image{
    self.uploadFile.thumbnail = image;
    self.imageView.image = image;

}

- (void)setIsUploading:(BOOL)isUploading {
    _isUploading = isUploading;

    bUploadLock = isUploading;
}

#pragma mark -- Notification Callback
- (void)onShareUploadSuccess:(NSNotification*)note {
    NSDictionary *dic = note.object;
    if ([dic isKindOfClass:[NSDictionary class]]) {
        NSString *shareUrl = dic[@"shareUrl"];
        NSString *segmentId = dic[@"segmentId"];
        if (self.isUploading && [segmentId isEqualToString:self.segmentId]) { //isUplaoding 没设置过来，标示 weakSelf没取到，则在这里补充处理一下.
            self.shareInstance.url = shareUrl;
            [self uploadSuccess];
        }
    }
}

- (void)onShareUploadFailed:(NSNotification*)note {
    NSDictionary *dic = note.object;
    if ([dic isKindOfClass:[NSDictionary class]]) {
        NSString *segmentId = dic[@"segmentId"];
        DJISkypixelError *error = dic[@"error"];
        if (self.isUploading && [segmentId isEqualToString:self.segmentId] && error) {
            DJIStyleAlertView *alert = [[DJIStyleAlertView alloc] initWithTitle:nil message:error.message cancelButtonTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) cancelButtonAction:NULL otherButtonTitle:nil otherButtonAction:NULL];
            [alert showWithDefaultStackAnimation:YES customStyle:DJIStyleAlertCustomStyle_Light];
        }
    }
}

#pragma mark - Action
- (void)OnBack:(id)sender {
    if (self.fromMakeMovieVC) {
        if (self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated: YES];
        }
    } else if (self.videoProject) {
        if ([[DJIVideoProjectManager sharedProjectManager] isProjectValid: self.videoProject]) {
            //如果是轻量编辑工程，返回轻量编辑界面
            if ([self.videoProject isLightEdit]) {
                DJIMakeMovieLiteVC *liteVC = [[DJIMakeMovieLiteVC alloc] initWithProject:self.videoProject];
                [self.navigationController pushViewController: liteVC animated: YES];
                
            }
            else {  //返回重型编辑 继续
                DJIMakeMovieVC* makeMovieVC = [[DJIMakeMovieVC alloc] initWithProject: self.videoProject];
                [self.navigationController pushViewController: makeMovieVC animated: YES];
            }
        } else {
            UIAlertController *alert = [BaseAutoLayout customAlertControllerWithTitle:NSLocalizedString(@"library_share_edit_video_project_broken", @"上传并分享界面-继续编辑-缺少片段提示 | 部分片段已被删除，无法继续编辑") message:nil preferredStyle:UIAlertControllerStyleAlert cancelTitle:NSLocalizedString(@"OK", nil) sourceView:nil];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)OnOnlyBack:(id)sender {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated: YES];
    }
    else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)OnFramesPost:(id)sender {
    weakSelf(weakSelf);
    //是否有正在执行的上传任务。（当前VC执行的上传任务不算）
    if (bUploadLock && !self.isUploading && sender) {
        [DJIStyleAlertView showAlertViewWithTitle:NSLocalizedString(@"nve_video_preview_failed_to_share", nil) message:NSLocalizedString(@"share_freeeye_upload_already_uploading", @"分享上传界面 已有在上传的任务 提示 | 暂有上传任务正在进行，请稍后再试.") btnTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) btnAction:NULL customStyle:DJIStyleAlertCustomStyle_Light];

        return;
    }

    void(^uploadAndPost)(void) = ^{
        //支持后台任务
        if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
            bgUploadIdentifier = UIBackgroundTaskInvalid;
        }
        //需求有变更， 功能留到下个版本上 （4.0.3 留）
        bgUploadIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            bgUploadIdentifier = UIBackgroundTaskInvalid;
        }];

        //添加上传任务
        NSMutableArray *uploadRequests = [NSMutableArray array];
        for (NSInteger i = 0; i < weakSelf.framesImageCount; i ++) {
            DJIMediaUploadRequest *request = [DJIMediaUploadRequest requestWithFilePath:[weakSelf localFrameImagePathAtIndex:i]];
            [uploadRequests addObject:request];
        }

        //如果正在上传，则直接显示进度
        if (weakSelf.isUploading) {
            [weakSelf.view addSubview: weakSelf.progressView];
            [weakSelf.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.edges.equalTo(weakSelf.view);
            }];
            [weakSelf.progressView resetProgressView];
            return;
        }
        weakSelf.progressView = [[DJIPulishArtWorkProgressView alloc] init];
        weakSelf.progressView.delegate = weakSelf;

        [weakSelf.view addSubview: weakSelf.progressView];
        [weakSelf.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(weakSelf.view);
        }];

        weakSelf.isUploading = YES;
        [weakSelf setUploadProgress:weakSelf.autoUploadResumeProgress];

        __block NSString *uploadedBgmUrl = nil;
        //先上传背景音乐
        if (weakSelf.framesBgm.shortMusicPath.length) {
            [[DJIMediaTransferTool sharedTool] addUploadTask:[NSURL fileURLWithPath:weakSelf.framesBgm.shortMusicPath] progressBlock:NULL finishBlock:^(DJIMediaUploadTask *task, BOOL allFinished) {
                if (task.state == DJIMediaUploadTaskState_Finished) {
                    uploadedBgmUrl = task.aliyunServerUrl;
                }
            }];

        }
        
        //shareInstance  和 tag数组要retain下来
        __strong ShareInstance *shareInstance = weakSelf.shareInstance;
        __strong NSArray    *tags = weakSelf.tagsArray;
        __strong DJIMakeMovieMusic *music = weakSelf.framesBgm;
        NSInteger framesCount = weakSelf.framesImageCount;
        __strong NSString *segmentId = weakSelf.segmentId;


        //总进度
        __block BOOL failEventDone = NO;    //一次 上传任务，只处理一次 失败的事件（多个文件上传，如果多个失败了， 会多次 返回fail事件
        weakSelf.frameUploadTasks = [[DJIMediaTransferTool sharedTool] addUploadTasksWithRequests:uploadRequests progressBlock:^(DJIMediaUploadTask *task) {
            CGFloat progress = [[DJIMediaTransferTool sharedTool] progressOfSerialTasks:task.taskId];
            [weakSelf setUploadProgress:progress];
            //抛出 上传进度通知
            [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadProgress object:@{@"tasks":[[DJIMediaTransferTool sharedTool] serialTasksOfTask:task.taskId],
                                                                                                                       @"segmentId":segmentId,
                                                                                                                       @"musicId":@(music.musicIdentifier)}];

        } finishBlock:^(DJIMediaUploadTask *task, BOOL allFinished) {
            //上传出错了
            if (task.state != DJIMediaUploadTaskState_Finished) {
                bUploadLock = NO;
                //停止后台任务
                if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
                    bgUploadIdentifier = UIBackgroundTaskInvalid;
                }

                //取消任务，不用提示
                if (task.state == DJIMediaUploadTaskState_Canceled) {
                }
                else if (!failEventDone) {
                    if ( weakSelf) {
                        DJIStyleAlertView *alert = [[DJIStyleAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"mine_upload_mission_cell_upload_failed_label", nil) cancelButtonTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) cancelButtonAction:^{

                        } otherButtonTitle:nil otherButtonAction:NULL];
                        [alert showWithDefaultStackAnimation:YES customStyle:DJIStyleAlertCustomStyle_Light];
                        [[DJIMediaTransferTool sharedTool] cancelAll];
                        //隐藏 进度条
                        [weakSelf setUploadProgress: 0.0];
                        [weakSelf resetProgressView];
                        weakSelf.isUploading = NO;
                    }
                    failEventDone = YES;
                    //抛出通知
                    [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadFailed object:@{@"tasks":[[DJIMediaTransferTool sharedTool] serialTasksOfTask:task.taskId],
                                                                                                                             @"segmentId":segmentId,
                                                                                                                             @"musicId":@(music.musicIdentifier)}];
                }
                return;

            }
            if (allFinished) {   //都完成了

                //停止后台任务
                if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
                    bgUploadIdentifier = UIBackgroundTaskInvalid;
                }
                //调用接口，通知后台，并获取 分享链接
                [[DJIShareProtocolManager sharedManager] sendVideoFrameShareInfo:shareInstance.title description:shareInstance.desc bucketName:task.bucketName pathPrefix:[task objectKeyPrefix] frameCount:framesCount tags:tags bgmUrl:uploadedBgmUrl completion:^(NSString *shareUrl, DJISkypixelError *error) {
                    //隐藏 进度条
                    [weakSelf setUploadProgress: 0.0];
                    [weakSelf resetProgressView];
                    weakSelf.isUploading = NO;
                    bUploadLock = NO;
                    if (!shareUrl.length) { //发生错误
                        if (weakSelf) {
                            DJIStyleAlertView *alert = [[DJIStyleAlertView alloc] initWithTitle:nil message:error.message cancelButtonTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) cancelButtonAction:NULL otherButtonTitle:nil otherButtonAction:NULL];
                            [alert showWithDefaultStackAnimation:YES customStyle:DJIStyleAlertCustomStyle_Light];
                        }
                        //抛出通知
                        [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadFailed object:@{@"tasks":[[DJIMediaTransferTool sharedTool] serialTasksOfTask:task.taskId],
                                                                                                                                 @"segmentId":segmentId?:@"",
                                                                                                                                 @"musicId":@(music.musicIdentifier),
                                                                                                                                 @"error":error}];
                    }
                    else {
                        weakSelf.shareInstance.url = shareUrl;
                        [weakSelf uploadSuccess];
                        //抛出通知
                        [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadSuccess object:@{@"tasks":[[DJIMediaTransferTool sharedTool] serialTasksOfTask:task.taskId],
                                                                                                                                  @"segmentId":segmentId?:@"",
                                                                                                                                  @"musicId":@(music.musicIdentifier),
                                                                                                                                      @"shareUrl":shareUrl}];
                        //发布了 freeeye作品，重查一下 作品信息
                        [[UserManager sharedUserManager].profileInstance.artworkPager requestAtPage:1 success:^(DJISkypixelPager *pager) {

                        } failure:^(AFHTTPRequestOperation *operation, DJISkypixelError *error) {

                        }];
                    }
                }];
            }
        }];
    };

    //检查网络情况，如果是wifi，可以直接上传
    Reachability *reach = [Reachability reachabilityWithHostName:[DJILogEvent sharedInstance].url_log_event];
    if ([reach currentReachabilityStatus] == ReachableViaWiFi) {
        uploadAndPost();
    }
    else {
        DJIAlertAction *continueAction = [DJIAlertAction actionWithTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) style:UIAlertActionStyleDefault handler:^(id action) {
            uploadAndPost();
        }];
        DJIAlertAction *cancelAction = [DJIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:NULL];
        DJIStyleAlertView *alert = [[DJIStyleAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"share_freeeye_upload_nowifi_tips", @"FREE EYE上传 非wifi下的提示 | 你当前网络状况不在WIFI下，是否继续上传?") actionList:@[cancelAction, continueAction]];
        [alert showWithDefaultStackAnimation:YES customStyle:DJIStyleAlertCustomStyle_Light];
    }


}

- (void)OnShare: (id)sender {

    //是否有正在执行的上传任务。（当前VC执行的上传任务不算）
    if (bUploadLock && !self.isUploading && sender) {
        [DJIStyleAlertView showAlertViewWithTitle:NSLocalizedString(@"nve_video_preview_failed_to_share", nil) message:NSLocalizedString(@"share_freeeye_upload_already_uploading", @"分享上传界面 已有在上传的任务 提示 | 暂有上传任务正在进行，请稍后再试.") btnTitle:NSLocalizedString(@"alertView_OKButtonTitle", nil) btnAction:NULL customStyle:DJIStyleAlertCustomStyle_Light];

        return;
    }

    __weak typeof(self) weakSelf = self;
    void(^shareBlock)(void) = ^{
        weakSelf.btnShare.enabled = NO;

        if ([[SettingManager sharedSettingManager] canUseNetworkToUpload]) {
            /*VEUploader *uploader  = [[UploadManager sharedUploadManager] uploaderForFile: weakSelf.uploadFile];
            if(uploader.uploadState == VEUploadStateSuccess && weakSelf.uploadFile.ddsID) {
                [weakSelf uploadSuccess];
                return;
            }*/

            [weakSelf saveContextToUserDefault];

            //如果正在上传，则直接显示进度
            if (weakSelf.isUploading) {
                [weakSelf.view addSubview: weakSelf.progressView];
                [weakSelf.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
                    make.edges.equalTo(weakSelf.view);
                }];
                [weakSelf.progressView resetProgressView];
                return;
            }
            //上传进度 视图 初始化
            weakSelf.progressView = [[DJIPulishArtWorkProgressView alloc] init];
            weakSelf.progressView.delegate = weakSelf;
            if (weakSelf.fromFPV) {
                [weakSelf.progressView hideFoldBtn];
            }
            [weakSelf.view addSubview: weakSelf.progressView];
            [weakSelf.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.edges.equalTo(weakSelf.view);
            }];

            weakSelf.isUploading = YES;
            weakSelf.fakeProgress = 0.f;
            [weakSelf startTimer];

            //上传相关参数初始化
            NSString* title = weakSelf.titleField.text;
            NSString* desc = @"";

            if (!title.length) {
                title = weakSelf.titleField.placeHolder;
            }
            //初始化 上报用的相关参数
            [self resetUploadReportParams];


            [DJIIdleTimerManager instance].isVideoEditing = YES;
            //将 文件上传skypixel 设为后台任务。
            if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
                bgUploadIdentifier = UIBackgroundTaskInvalid;
            }
            //需求有变更， 功能留到下个版本上 （4.0.3 留）
            bgUploadIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                bgUploadIdentifier = UIBackgroundTaskInvalid;
             }];
            [weakSelf setUploadProgress: weakSelf.autoUploadResumeProgress];
            //
            dispatch_run_defaultQueue(^{
                [[UploadManager sharedUploadManager] addUploadTaskForFile:weakSelf.uploadFile withTitle:title description:desc tagList:weakSelf.tagsArray success:NULL failure:^(UploadFailureReason reason) {
                    if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
                        [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
                        bgUploadIdentifier = UIBackgroundTaskInvalid;
                    }
                    [DJIIdleTimerManager instance].isVideoEditing = NO;
                    [weakSelf uploadFailureWithReason:reason];
                    bUploadLock = NO;
                }];

                [[UploadManager sharedUploadManager] fireKey:UPLOADMANAGER_KEY_MINEVC WithData:@{@"success": @(YES), @"fileName": weakSelf.uploadFile.path.lastPathComponent}];
                weakSelf.uploader = [[UploadManager sharedUploadManager] uploaderForFile: weakSelf.uploadFile];
                weakSelf.uploader.progressHandler = ^(VEUploader* uploader, CGFloat progress) {
                    progress = MAX(progress * 0.7f + weakSelf.fakeProgress, progress);
                    //抛出 上传进度通知
                    uploader.fakeProgress = MAX(uploader.fakeProgress, progress);   //也要抛出 假进度，保持 exploreVC与这里的进度一致
                    [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadProgress object:uploader];
                    if (weakSelf.isUploading == NO) {
                        return ;
                    }

                    [weakSelf setUploadProgress: MAX(uploader.fakeProgress, weakSelf.progressView.progress)];
                };
                weakSelf.uploader.cellCompletion = ^(VEUploader *uploader, BOOL success) {
                    bUploadLock = NO;
                    if (bgUploadIdentifier != UIBackgroundTaskInvalid) {
                        [[UIApplication sharedApplication] endBackgroundTask:bgUploadIdentifier];
                        bgUploadIdentifier = UIBackgroundTaskInvalid;
                    }
                    if (success) {
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            [DJIIdleTimerManager instance].isVideoEditing = NO;
                            //抛出通知
                            [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadSuccess object:uploader];
                            if (weakSelf) {
                                [weakSelf uploadSuccess];
                            }
                        }];
                    }
                    else {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadFailed object:uploader];

                    }
                };
            });

        } else {
            //        [self.imageView setNetWorkErrorView: self.networkErrorView];
            NSString *str;
            if(![[SettingManager sharedSettingManager] hasNetWork]) {
                str = LOCALIZE(@"college_no_network_detail");
            }
            else if (![[SettingManager sharedSettingManager] canUseNetworkToUpload]) {
                str = LOCALIZE(@"mine_settings_can_not_use_cellular_to_upload");
            }
            else {
                str = LOCALIZE(@"college_no_network");
            }
            [weakSelf.view showTipsViewWhitText:str];
            weakSelf.btnShare.enabled = YES;
        }

    };

    shareBlock();

}

- (void)OnShareLater: (id)sender {

    __weak typeof(self) weakSelf = self;
    void (^dismissHandler)(UIAlertAction* action) = ^(UIAlertAction *action){
        if (self.uploadFile.isPhoto) {
            [Flurry djiLogEvent:@"v2_photo_upload_later"];
        } else {
            [Flurry djiLogEvent:@"v2_video_upload_later"];
        }

        [self doDismissWithCompleteBlock:^{
            //            if(weakSelf.mainVC.selectedIndex == 3) return ;
            //            weakSelf.mainVC.selectedIndex = 3;
            //            MineVC *mineVC = (MineVC *)[(UINavigationController *)weakSelf.mainVC.viewControllers[3] topViewController];
            //            [mineVC enterUploadMissionVC];
        }];
    };
    DJIAlertAction *cancel = [DJIAlertAction actionWithTitle:NSLocalizedString(@"library_upload_cancel_upload", @"分享页面放弃分享 | 放弃分享") style:UIAlertActionStyleDefault handler:dismissHandler];
    DJIAlertAction *upload = [DJIAlertAction actionWithTitle:NSLocalizedString(@"library_upload_continue_confirm", @"分享页面继续分享 | 继续分享") style:UIAlertActionStyleDefault handler:nil];
    DJIStyleAlertView *styleAlert = [[DJIStyleAlertView alloc] initWithTitle:NSLocalizedString(@"library_upload_cancel_alert_title", nil) message:nil actionList:@[cancel, upload]];
    [styleAlert showWithDefaultStackAnimation:YES customStyle:DJIStyleAlertCustomStyle_Light];
}

- (void)OnPreview: (id)sender {
    if (self.shareSource == MediaShareSource_Frames) {
        //序列帧 预览
        NSMutableArray *paths = [NSMutableArray arrayWithCapacity:self.framesImageCount];
        for (NSInteger i = 0; i < self.framesImageCount; i ++) {
            [paths addObject:[self localFrameImagePathAtIndex:i]];
        }
        DJILayoutPreviewVC *previewVC = [[DJILayoutPreviewVC alloc] initWithLayoutPaths:paths bgmPath:self.framesBgm.shortMusicPath];
        [self.navigationController pushViewController:previewVC animated:YES];
    }
    else {
        if (self.uploadFile.isPhoto) {
            [Flurry djiLogEvent:@"v3_ed_Photo_shatre_review"];
            if (self.uploadFile.image) {
                CGRect fromRect = self.imageView.frame;
                [DJIExploreDisplayImageVC showExploreDisplayImageVCWithExploreItem:nil previewImage:self.uploadFile.image originImageFrame:fromRect hideSatatusBarWhenDismiss:[UIApplication sharedApplication].statusBarHidden disableDismissOritation:YES];
                return;
            }

            PHAsset *asset = nil;
            if (self.uploadFile.phAsset) {
                asset = self.uploadFile.phAsset;
            }else{
                PHFetchResult *assetResult = [PHAsset fetchAssetsWithALAssetURLs:@[self.uploadFile.url] options:nil];
                asset = [assetResult firstObject];
            }

            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.networkAccessAllowed = NO;

            weakSelf(target);
            [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:PHImageManagerMaximumSize contentMode:PHImageContentModeAspectFill options:options resultHandler:^(UIImage *result, NSDictionary *info) {
                UIImage *image = result;
                CGRect fromRect = target.imageView.frame;

                dispatch_main_async(^{
                    [DJIExploreDisplayImageVC showExploreDisplayImageVCWithExploreItem:nil previewImage:image originImageFrame:fromRect hideSatatusBarWhenDismiss:[UIApplication sharedApplication].statusBarHidden disableDismissOritation:YES];
                });
                return;
            }];
        }else{
            [Flurry djiLogEvent:@"v3_ed_video_share_play"];
            CSegment *segment = self.uploadFile.currentItem;
            if (!segment) {
                segment = [[CSegment alloc]init];
                AVURLAsset *asset =  (AVURLAsset*)[AVAsset assetWithURL:self.uploadFile.url];
                segment.asset = asset;
                segment.newMark = NO;
                segment.fileURL = self.uploadFile.url;
                segment.assetFrom = SegmentFrom_system;
            }
            [self resetPresentProperties:self.imageView];

            DJIPreviewVC *previewVC = [[DJIPreviewVC alloc] initWithArrayPreviewOnly:@[segment]];
            previewVC.currentItem = segment;
            previewVC.disablePortait = self.fromFPV;
            previewVC.type = DJIPreviewVCTypeVideo;
            previewVC.autoPlay = YES;
            [self presentViewController:previewVC animated:YES completion:nil];
            return;

        }
    }

}

- (void)OnAddTag: (id)sender {
    [self OnTapSelectTags];
}

- (void)OnFakeProgressTimer: (NSTimer *)timer {
    CGFloat progress = (CGFloat)(arc4random() % 6) / 100.f;
    self.fakeProgress += progress;

    if (self.fakeProgress >= 0.3) {
        [self invalidateTimer];
        self.fakeProgress = 0.3f;
    }
}

- (void)OnTapSelectTags {
    UploadTagSelectVC *vc = [[UploadTagSelectVC alloc] initWithTagsArray:self.tagsArray withLandscapeLayout: self.fromFPV];
    vc.delegate = self;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)OnCancelUpload {
    weakSelf(target);
    UIAlertController *alert = [BaseAutoLayout customAlertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet cancelTitle:NSLocalizedString(@"Cancel", nil) sourceView:nil];
    UIAlertAction* confirmAction = [UIAlertAction actionWithTitle: NSLocalizedString(@"mine_upload_mission_cancel_alert", nil) style: UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if (target.shareSource == MediaShareSource_Media) {
            [target invalidateTimer];
            [[UploadManager sharedUploadManager] cancelUploadingForFile: target.uploadFile];
            target.fakeProgress = 0.f;

            [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadFailed object:target.uploader];
        }
        else {
            [[DJIMediaTransferTool sharedTool] cancelAll];
            [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadFailed object:@{@"tasks":target.frameUploadTasks,
                                                                                                                     @"segmentId":target.segmentId,
                                                                                                                     @"musicId":@(target.framesBgm.musicIdentifier)}];
        }
        target.isUploading = NO;
        bUploadLock = NO;
        target.btnShare.enabled = YES;
        [target setUploadProgress: 0.0];
        [target resetProgressView];
    }];

    [alert addAction: confirmAction];
    [self presentViewController: alert animated: YES completion: nil];
}

- (void)OnSetCover:(UIButton*)btn{
    if (!self.coverVC) {
        CSegment *segment = [[CSegment alloc]init];
        AVURLAsset *asset =  (AVURLAsset*)[AVAsset assetWithURL:self.uploadFile.url];
        segment.asset = asset;
        segment.newMark = NO;
        segment.fileURL = self.uploadFile.url;
        segment.assetFrom = SegmentFrom_system;

        self.coverVC = [[DJISelectCoverVC alloc] initWithSegment:segment withLandscapeLayout:self.fromFPV];
        self.coverVC.delegate = self;
        [self presentViewController: [[DefaultOrientationNC alloc] initWithRootViewController: self.coverVC] animated:YES completion:nil];
    }
}

#pragma mark -- UI Creation
- (void)buildImageView {
    self.imageView = [[UIImageView alloc] init];
    if (self.shareSource == MediaShareSource_Frames) {
        self.imageView.image = [self thumbnailForFrames];
    }
    else {
        self.imageView.image = self.uploadFile.thumbnail;
    }
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    [self.view addSubview: self.imageView];

    self.imageView.userInteractionEnabled = YES;
    [self.imageView addGestureRecognizer: [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(OnPreview:)]];

    if (IS_IPAD) {
        [self.imageView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.view).offset(260.f);
            make.right.equalTo(self.view).offset(-260.f);
            make.top.equalTo(self.pageHeaderView.mas_bottom).offset(40.f);
            make.height.equalTo(self.imageView.mas_width).multipliedBy(9/16.0);
        }];
    } else {
        if (!self.fromFPV) {
            [self.imageView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(self.view).offset(75.f);
                make.right.equalTo(self.view).offset(-75.f);
                make.top.equalTo(self.pageHeaderView.mas_bottom).offset(IS_IPHONE5 ? 14.f : 18.f);
                make.height.mas_equalTo(135.f);
            }];
        }
        else {  //强制横屏时，布局不同
            [self.imageView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(self.view).offset(50.f);
                make.top.equalTo(self.pageHeaderView.mas_bottom).offset(5);
                make.height.mas_equalTo(125.f);
                make.width.mas_equalTo(209.f);   //高宽比
            }];
        }
    }

    UIView* maskView = [[UIView alloc] init];
    maskView.backgroundColor = UIColorFromRGBA(0x000000, 0.1);
    [self.imageView addSubview: maskView];

    [maskView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.imageView);
    }];
}

- (void)buildPlayButton {
    self.playButton = [UIButton buttonWithType: UIButtonTypeCustom];
    [self.playButton setImage: [UIImage imageNamed: @"nve_preview_play_icon"] forState: UIControlStateNormal];
    //    [self.playButton setImage: [UIImage imageNamed: @"mine_upload_video_preview_btn_large"] forState: UIControlStateNormal];
    [self.playButton addTarget: self action: @selector(OnPreview:) forControlEvents: UIControlEventTouchUpInside];
    [self.view addSubview: self.playButton];

    [self.playButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(self.imageView);
    }];
}

- (void)buildCoverButton{
    self.coverButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.coverButton setImage:[UIImage imageNamed:@"nve_creation_pencil_icon"] forState:UIControlStateNormal];
    [self.coverButton setImage:[UIImage imageNamed:@"nve_creation_pencil_highlighted_icon"] forState:UIControlStateHighlighted];
    [self.coverButton setTitle:NSLocalizedString(@"nve_sharevc_cover_button_title", @"分享界面视频封面按钮文案 | 封面") forState:UIControlStateNormal];
    [self.coverButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.coverButton setTitleColor:UIColorFromRGB(0x89C2F3) forState:UIControlStateHighlighted];
    [BaseAutoLayout makeSpaceForButton:self.coverButton withSpace:3];
    //    self.coverButton.backgroundColor = UIColorFromRGB(0x0F83E9);
    [self.coverButton setBackgroundImage:[UIImage imageWithColor:UIColorFromRGB(0x0F83E9)] forState:UIControlStateNormal];
    [self.coverButton setBackgroundImage:[UIImage imageWithColor:UIColorFromRGB(0x57A8EF)] forState:UIControlStateHighlighted];
    self.coverButton.clipsToBounds = YES;
    self.coverButton.titleLabel.font = [UIFont fontWithName:MAIN_FONT size:12.];
    self.coverButton.adjustsImageWhenHighlighted = NO;
    [self.coverButton setHitTestEdgeInsets:UIEdgeInsetsMake(-5, -5, -5, -5)];
    [self.coverButton addTarget:self action:@selector(OnSetCover:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.coverButton];

    CGFloat width = 0, height = 0, offsetX = 0;
    if (IS_IPHONE) {
        width = 53, height = 22, offsetX = 6.5;
    }else{
        width = 68, height = 28, offsetX = 10;
    }
    [self.coverButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.imageView.mas_right).offset(-offsetX);
        make.bottom.equalTo(self.imageView.mas_bottom).offset(-offsetX);
        make.height.equalTo([NSNumber numberWithFloat:height]);
        make.width.equalTo([NSNumber numberWithFloat:width]);
    }];
    self.coverButton.layer.cornerRadius = height / 2;
}

- (void)buildShareContent {
    self.titleField = [[PlaceHolderTextView alloc] init];
    self.titleField.backgroundColor = UIColorFromRGB(0xF6F6F6);
    self.titleField.font = [UIFont fontWithName: MAIN_FONT size: 15.f];
    self.titleField.textColor = UIColorFromRGB(0x4A4A4A);
    self.titleField.placeHolderLabel.textColor = UIColorFromRGB(0x9B9B9B);
    self.titleField.text = [self titleKeyInUserDefaults];
    self.titleField.delegate = self;
    [self.view addSubview: self.titleField];

    if (IS_IPAD) {
        [self.titleField mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.imageView.mas_bottom).offset(40.f);
            make.left.equalTo(self.view).offset(125.f);
            make.right.equalTo(self.view).offset(-125.f);
            make.height.mas_equalTo(44.f);
        }];
    } else {
        if (!self.fromFPV) {
            [self.titleField mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(self.imageView.mas_bottom).offset(IS_IPHONE5 ? 14.f : 18.f);
                make.left.equalTo(self.view).offset(38.f);
                make.right.equalTo(self.view).offset(-38.f);
                make.height.mas_equalTo(61.f);
            }];
        }
        else {
            [self.titleField mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(self.imageView);
                make.left.equalTo(self.imageView.mas_right).offset(15.f);
                make.right.equalTo(self.view).offset(-50.f);
                make.height.equalTo(self.imageView);
            }];
        }
    }

    //title 输入 与 标签 之间的分割线
    UIView *line = [UIView new];
    line.backgroundColor = UIColorFromRGB(0xD8D8D8);
    [self.view addSubview:line];
    if (!self.fromFPV) {
        [line mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.equalTo(self.titleField);
            make.height.mas_equalTo(0.5f);
            make.top.equalTo(self.titleField.mas_bottom).offset(10);
        }];
    }
    else {
        if (IS_IPAD) {
            [line mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.right.equalTo(self.titleField);
                make.height.mas_equalTo(0.5f);
                make.top.equalTo(self.titleField.mas_bottom).offset(10);
            }];
        }
        else {
            [line mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(self.imageView);
                make.right.equalTo(self.titleField);
                make.height.mas_equalTo(0.5f);
                make.top.equalTo(self.titleField.mas_bottom).offset(10);
            }];
        }
    }


    //标签部分
    self.tagsView = [[UIScrollView alloc] init];
    //self.tagsView.backgroundColor = UIColorFromRGB(0xF6F6F6);
    self.tagsView.showsHorizontalScrollIndicator = self.tagsView.showsVerticalScrollIndicator = NO;
    [self.view addSubview: self.tagsView];

    if (!self.fromFPV) {
        [self.tagsView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(line.mas_bottom).offset(10);
            make.left.right.equalTo(line);
            make.height.mas_equalTo(IS_IPAD?52.f:44.f);
        }];
    }
    else {
        [self.tagsView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(line.mas_bottom).offset(10);
            make.left.right.equalTo(line);
            make.height.mas_equalTo(IS_IPAD?40.f:28.f);
        }];
    }

    /* 去掉依赖CDjiTemplate的tag部分
    NSDictionary* shareContent = self.uploadFile.tpl.shareContent;
    NSArray* shareTags = [shareContent objectForKey: @"tags"];
    NSMutableArray* shareAllTags = [NSMutableArray array];
    for (NSDictionary* tag in shareTags) {
        [shareAllTags addObject: [tag objectForKey: [ComHelper countryCodeFromLocal]]];
    }
    self.tagsArray = shareAllTags;
    */

    NSString* tagsString = [[NSUserDefaults standardUserDefaults] objectForKey: [self tagsKeyInUserDefaults]];
    NSArray* tags = [tagsString componentsSeparatedByString: @", "];
    if (tags.count > 0) {
        NSMutableArray* allTags = [NSMutableArray array];
        if (self.tagsArray.count > 0) {
            [allTags addObjectsFromArray:self.tagsArray];
        }
        for (NSString* tag in tags) {
            if (![allTags containsObject:tag]) {
                [allTags addObject:tag];
            }
        }
        self.tagsArray = allTags;
    }
    
    [self reloadTagsView];
}

- (void)buildShareCenterView {
    //freeeye分享，没有 shareMore
    self.shareCenterView = (self.shareSource == MediaShareSource_Frames)?[[DJIShareCenterView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width - 38*2, 0) lightMode:YES]:
    [[DJIShareCenterView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width - 38*2, 0)];
    self.shareCenterView.delegate = self;
    self.shareCenterView.supportOrientationLandscape = self.fromFPV;
    [self.view addSubview: self.shareCenterView];

    if (IS_IPAD) {
        [self.shareCenterView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.tagsView.mas_bottom).offset(20.f);
            make.left.right.equalTo(self.tagsView);
            make.height.mas_equalTo(130.f);
        }];
    } else {
        if (!self.fromFPV) {
            [self.shareCenterView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(self.tagsView.mas_bottom).offset(IS_IPHONE5 ? 12.f : 15.f);
                make.left.equalTo(self.view).offset(38.f);
                make.right.equalTo(self.view).offset(-38.f);
                make.height.mas_greaterThanOrEqualTo(IS_IPHONE5 ? 74.f : 150.f);
                make.bottom.equalTo(self.view);
            }];
        }
        else {
            [self.shareCenterView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.equalTo(self.tagsView.mas_bottom).offset(10);
                make.left.equalTo(self.imageView);
                make.right.equalTo(self.titleField);
                make.bottom.equalTo(self.view);
            }];
        }
    }
}


- (UIButton *)createShareButton {
    self.btnShare = [self createHeaderTextBtn: NSLocalizedString(@"share", nil)];
    [self.btnShare setTitleColor: UIColorFromRGB(0x1C8CEF) forState: UIControlStateNormal];

    if (self.shareSource == MediaShareSource_Frames) {
        [self.btnShare addTarget: self action: @selector(OnFramesPost:) forControlEvents: UIControlEventTouchUpInside];
    }
    else {
        [self.btnShare addTarget: self action: @selector(OnShare:) forControlEvents: UIControlEventTouchUpInside];
    }
    return self.btnShare;
}

- (UILabel*) createLabelWithText:(NSString*)text {
    UIFont *font = [UIFont fontWithName: MAIN_FONT size: 12.f];
    CGSize size = [text sizeWithAttributes: @{NSFontAttributeName : font}];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, size.width + 32, 22)];
    label.layer.borderColor = UIColorFromRGB(0xD7D7D7).CGColor;
    label.layer.borderWidth = 1.f / [UIScreen mainScreen].scale;
    label.layer.cornerRadius = label.height / 2.f;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColorFromRGB(0x9B9B9B);
    label.font = font;
    label.backgroundColor = [UIColor clearColor];
    label.clipsToBounds = YES;
    label.userInteractionEnabled = YES;
    label.text = text;
    return label;
}

- (UIButton *)createButtonWithText: (NSString *)text image: (UIImage *)image {
    UIFont* font = [UIFont fontWithName: MAIN_FONT size: 12.f];
    CGSize size = [text sizeWithAttributes:@{NSFontAttributeName:font}];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, size.width + 32, 22);
    button.backgroundColor = [UIColor clearColor];
    button.layer.borderColor = UIColorFromRGB(0xD7D7D7).CGColor;
    button.layer.borderWidth = 1.0f / [UIScreen mainScreen].scale;
    button.layer.cornerRadius = button.height / 2.f;
    button.titleLabel.font = font;
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitleColor:UIColorFromRGB(0x9B9B9B) forState:UIControlStateNormal];
    [button setImage:image forState:UIControlStateNormal];
    button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
    return button;
}

- (void)resetProgressView {
    [self.progressView updateProgress: 0.f];
    [self.progressView hideProgressView];
}

- (void)reloadTagsView {
    NSMutableArray *tagsLabelArray = [NSMutableArray array];

    // BugFix:iOSGOIOS-3448 点选空白区域也可以显示选择Tag了
    if (!self.tagsViewTapRec) {
        self.tagsViewTapRec = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(OnAddTag:)];
        self.tagsViewTapRec.numberOfTapsRequired = 1;
        [self.tagsView addGestureRecognizer:self.tagsViewTapRec];
    }

    if(self.tagsArray == nil || self.tagsArray.count == 0) {
        UIButton* btnAddTag = [self createButtonWithText:NSLocalizedString(@"library_share_add_tag", @"添加标签") image:[UIImage imageNamed:@"explore_publish_artwork_add_tags"]];
        [btnAddTag addTarget: self action: @selector(OnAddTag:) forControlEvents: UIControlEventTouchUpInside];
        btnAddTag.width = btnAddTag.width + 8;
        [tagsLabelArray addObject: btnAddTag];
    } else {
        for (NSString *tag in self.tagsArray) {
            UILabel* tagLabel = [self createLabelWithText:tag];
            [tagsLabelArray addObject: tagLabel];
            __weak typeof(self) weakSelf = self;
            [tagLabel setTapActionWithBlock:^{
                [weakSelf OnTapSelectTags];
            }];
        }
    }

    for (UIView *subView in self.tagsView.subviews) {
        [subView removeFromSuperview];
    }

    CGFloat x = 0;
    CGFloat y = IS_IPAD ? 15.f : (self.fromFPV?0:4.f);
    CGFloat tagAlign = 8.0f;
    for (UILabel *label in tagsLabelArray) {
        [self.tagsView addSubview:label];
        [label mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self.tagsView).offset(x);
            make.top.equalTo(self.tagsView).offset(y);
            make.width.mas_equalTo(label.width);
            make.height.equalTo(self.tagsView).offset(-y*2);
        }];
        
        x += tagAlign + label.width;
    }
    //布局
    if (self.fromFPV) { //只有横屏需要布局
        x = self.tagsView.subviews.firstObject.x;
        for (UIView *subView in self.tagsView.subviews) {
            CGFloat width = subView.width;
            [subView mas_remakeConstraints:^(MASConstraintMaker *make) {
                make.width.mas_equalTo(width);
                make.left.equalTo(self.tagsView).offset(x);
                make.top.height.equalTo(self.tagsView);
            }];
            x += tagAlign + width;
        }
    }

    if (x < self.tagsView.frame.size.width) {
        self.tagsView.contentSize = CGSizeMake(self.tagsView.frame.size.width, self.tagsView.frame.size.height);
    } else {
        self.tagsView.contentSize = CGSizeMake(x, self.tagsView.frame.size.height);
    }
}


- (void)showDocumentInteraction {
    NSURL *URL = self.shareInstance.fileUrl;
    if (URL) {
        //这里 由于 本地视频 URL调用 UIDocumentInteractionController  会发送失败，因此，先移到本地沙盒目录后，再进行分享
        NSURL *tempDestUrl = [NSURL fileURLWithPath:[[DJIFileHelper fetchTempPath] stringByAppendingPathComponent:[[URL path] lastPathComponent]]];
        [[NSFileManager defaultManager] copyItemAtURL:URL
                                                toURL:tempDestUrl
                                                error:nil];
        // Initialize Document Interaction Controller
        self.documentController = [UIDocumentInteractionController interactionControllerWithURL:tempDestUrl];
        // Configure Document Interaction Controller
        [self.documentController setDelegate:self];
        // Present Open In Menu
        if (IS_IPAD) {
            CGRect rectForAppearing = [self.view convertRect:self.shareCenterView.frame toView:self.view];
            [self.documentController presentOptionsMenuFromRect:rectForAppearing inView:self.view animated:YES];
        }
        else {
            [self.documentController presentOptionsMenuFromRect:CGRectZero inView:self.view animated:YES];
        }
    }
}

#pragma mark - Private
- (NSString *)getShareContent:(NSString*)contentKey {
    /* 去掉以来ctemplate逻辑的部分
    NSDictionary* shareContent = self.uploadFile.tpl.shareContent;
    NSDictionary* dict = [shareContent objectForKey: contentKey];
    return [dict objectForKey: [ComHelper countryCodeFromLocal]];
    */
    return nil;
}

- (void) doDismissWithCompleteBlock:(void (^)(void))complete {
    if (self.isUploading) {
        [[UploadManager sharedUploadManager] cancelUploadingForFile:self.uploadFile];
    }
    [self saveContextToUserDefault];
    [self.navigationController dismissViewControllerAnimated:YES completion:complete];
}

- (void)setupRandomText {
    NSUInteger index = rand() % 5 + 1;
    NSString *titleKey = [NSString stringWithFormat:@"library_upload_title_placeholder_%@", @(index)];
    NSString *descKey = [NSString stringWithFormat:@"library_upload_description_placeholder_%@", @(index)];
    
    NSString* titleString = NSLocalizedString(titleKey, nil);
    if (!self.uploadFile.isPhoto && self.shareSource == MediaShareSource_Media) {   //带设备的视频 分享title不同
        NSString *productClass = [self productClassOfShareItem];
        if (productClass) {   //显示 拍摄的设备名
            NSString *equipment = [ProductUtils productNameWithProductClass:productClass];
            titleString = equipment.length?[NSString stringWithFormat:NSLocalizedString(@"library_upload_title_placeholder_equipment", @"快来看看我用 %@拍摄的一部短片 (%@ 是占位符，标示设备名） | 快来看看我用 %@ 拍摄的一部短片"), equipment]:NSLocalizedString(@"library_upload_description_placeholder_1", nil);
        }
        else {
            titleString = NSLocalizedString(@"library_upload_description_placeholder_1", nil);
            
        }
    }
    
    if (titleString.length > 0) {
        NSAttributedString* attrString = [[NSAttributedString alloc] initWithString:titleString attributes:@{NSForegroundColorAttributeName:UIColorFromRGB(0x9b9b9b)}];
        self.titleField.attributedText = attrString;
    }

}

- (ShareInstance *)shareInstance {
    if (!_shareInstance) {
        //为序列帧 生成 shareInstance
        if (self.shareSource == MediaShareSource_Frames) {  //序列帧 数据源不同
            _shareInstance = [ShareInstance new];
            _shareInstance.thumbnail = [self thumbnailForFrames];
            _shareInstance.type = ShareInstanceTypeWebPage;
        }
        else {
            _shareInstance = [self createShareInstanceForFile: self.uploadFile];

        }
    }
    NSString* title = self.titleField.text;
    NSString* desc = @"";
    if (!title.length) {
        title = self.titleField.placeHolder;
    }

    _shareInstance.title = title;
    _shareInstance.desc = desc;

    return _shareInstance;
}

- (UILabel *)networkErrorView {
    if (!_networkErrorView) {
        _networkErrorView = [BaseAutoLayout customLabelWithText:nil fontSize:15 color:[UIColor whiteColor] numberOfLines:0];
        _networkErrorView.layer.cornerRadius = 3.f;
        _networkErrorView.backgroundColor = [UIColor blackColor];
        _networkErrorView.clipsToBounds = _networkErrorView.layer.masksToBounds = YES;
    }

    return _networkErrorView;
}





- (NSString *)titleKeyInUserDefaults {
    if (self.uploadFile) {
        NSString *key = [self.uploadFile.path.lastPathComponent stringByAppendingString:@"_upload_title"];
        return key;
    }
    return @"share_default_upload_title";
}

- (NSString *)descriptionKeyInUserDefaults {
    if (self.uploadFile) {
        NSString *key = [self.uploadFile.path.lastPathComponent stringByAppendingString:@"_upload_description"];
        return key;
    }
    return @"share_default_upload_description";
}

- (NSString *) tagsKeyInUserDefaults {
    if (self.uploadFile) {
        NSString *key = [self.uploadFile.path.lastPathComponent stringByAppendingString:@"_tags"];
        return key;
    }
    return @"share_default_tags";
}

- (NSString*) tagsString {
    NSString *str = nil;
    if(self.tagsArray && self.tagsArray.count) {
        str = [self.tagsArray componentsJoinedByString:@", "];
    }
    return str;
}


- (void)saveContextToUserDefault {
    [[NSUserDefaults standardUserDefaults] setObject:self.titleField.text forKey:[self titleKeyInUserDefaults]];
    //[[NSUserDefaults standardUserDefaults] setObject:self.descView.text forKey:[self descriptionKeyInUserDefaults]];
    NSString *tagsString = [self tagsString];
    if(tagsString) {
        [[NSUserDefaults standardUserDefaults] setObject:tagsString forKey:[self tagsKeyInUserDefaults]];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)startTimer {
    if (self.progressTimer != nil) {
        return ;
    }

    __weak typeof(self) weakSelf = self;
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval: 0.6f target: weakSelf selector: @selector(OnFakeProgressTimer:) userInfo: nil repeats: YES];
}

- (void)invalidateTimer {
    if (self.progressTimer) {
        [self.progressTimer invalidate];
        self.progressTimer = nil;
    }
}

- (void)setUploadProgress: (CGFloat)progress {
    [self.progressView updateProgress: progress];
}

- (void)image: (UIImage *) image didFinishSavingWithError: (NSError *) error contextInfo: (void *) contextInfo
{
    NSLog(@"");
}

- (void)uploadSuccess {
    self.isUploading = NO;
    [self resetProgressView];

    void(^shareBlock)(NSString*) = ^(NSString* assetUrlString){
        self.shareInstance.socialMedia = [self.shareCenterView socialMedia];
        self.shareInstance.assetUrlString = assetUrlString;
        if (self.shareCenterView.socialMedia == SocialMediaCopyURL) {
            [[BaseShare sharer] handleShareInstance: self.shareInstance result: YES];
        }
        [self.shareInstance flurry];

        [self invalidateTimer];
        self.btnShare.enabled = YES;
        self.shouldJumpToProfile = YES; //Log v3_ed_video_share_wechat_moment  =====     根据 fromMakeMovie  判断是否 是单个视频分享
        if (!self.fromMakeMovieVC) {    //单个视频分享
            switch (self.shareCenterView.socialMedia) {
                case SocialMediaCopyURL:
                    [Flurry djiLogEvent:@"v3_ed_video_share_copylink_single"];
                    break;
                case SocialMediaFacebook:
                    [Flurry djiLogEvent:@"v3_ed_video_share_facebook_single"];
                    break;
                case SocialMediaTwitter:
                    [Flurry djiLogEvent:@"v3_ed_video_share_twitter_single"];
                    break;
                case SocialMediaWhatsApp:
                    [Flurry djiLogEvent:@"v3_ed_video_share_whatsapp_single"];
                    break;
                case SocialMediaInstagram:
                    [Flurry djiLogEvent:@"v3_ed_video_share_instagram_single"];
                    break;
                case SocialMediaWeibo:
                    [Flurry djiLogEvent:@"v3_ed_video_share_sina_singe"];
                    break;
                case SocialMediaQQ:
                    [Flurry djiLogEvent:@"v3_ed_video_share_qq_single"];
                    break;
                case SocialMediaWeChatSession:
                    [Flurry djiLogEvent:@"v3_ed_video_share_wechat_friend_single"];
                    break;
                case SocialMediaWeChatTimeline:
                    [Flurry djiLogEvent:@"v3_ed_video_share_wechat_moment_single"];
                    break;

                default:
                    break;
            }
        }
        else {
            switch (self.shareCenterView.socialMedia) {
                case SocialMediaCopyURL:
                    [Flurry djiLogEvent:@"v3_ed_video_share_copylink"];
                    break;
                case SocialMediaFacebook:
                    if([NSLocale currentLanguage] == DJILocaleLanguage_Chinese) {
                        [Flurry djiLogEvent:@"v3_ed_video_share_facebook_CN"];
                    }else {
                        [Flurry djiLogEvent:@"v3_ed_video_share_facebook"];
                    }
                    break;
                case SocialMediaTwitter:
                    if([NSLocale currentLanguage] == DJILocaleLanguage_Chinese) {
                        [Flurry djiLogEvent:@"v3_ed_video_share_twitter_CN"];
                    }else {
                        [Flurry djiLogEvent:@"v3_ed_video_share_twitter"];
                    }
                    break;
                case SocialMediaWhatsApp:
                    [Flurry djiLogEvent:@"v3_ed_video_share_whatsapp"];
                    break;
                case SocialMediaInstagram:
                    [Flurry djiLogEvent:@"v3_ed_video_share_instagram"];
                    break;
                case SocialMediaWeibo:
                    [Flurry djiLogEvent:@"v3_ed_video_share_sina"];
                    break;
                case SocialMediaQQ:
                    [Flurry djiLogEvent:@"v3_ed_video_share_qq"];
                    break;
                case SocialMediaWeChatSession:
                    if([NSLocale currentLanguage] == DJILocaleLanguage_Chinese) {
                        [Flurry djiLogEvent:@"v3_ed_video_share_wechat_friend"];
                    }else {
                        [Flurry djiLogEvent:@"v3_ed_video_share_wechat_friend_CN"];
                    }
                    break;
                case SocialMediaWeChatTimeline:
                    if([NSLocale currentLanguage] == DJILocaleLanguage_Chinese) {
                        [Flurry djiLogEvent:@"v3_ed_video_share_wechat_moment"];
                    }else {
                        [Flurry djiLogEvent:@"v3_ed_video_share_wechat_moment_CN"];
                    }
                    break;

                default:
                    break;
            }
        }
        [Flurry djiLogEvent:@"v3_ed_video_share_play"];
        //如果 app在后台，上传完毕了，则暂时不用呼起第三方 分享
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            return;
        }

        __weak typeof(self) weakSelf = self;
        //微信分享，可以以两种形式分享出去.  只支持 图片和视频文件
        if (self.shareInstance.socialMedia == SocialMediaWeChatSession && self.shareSource == MediaShareSource_Media) {
            UIAlertController *alert = [BaseAutoLayout customAlertControllerWithTitle:nil
                                                                              message:NSLocalizedString(@"library_share_weixin_share_type", @"分享到微信形式 标题 | 选择分享微信好友形式")
                                                                       preferredStyle:UIAlertControllerStyleActionSheet
                                                                          cancelTitle:NSLocalizedString(@"Cancel", nil)
                                                                           sourceView:nil];
            UIAlertAction *linkAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"library_share_weixin_with_link", @"分享到微信 链接形式 | 链接形式分享") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                BOOL success = [[ShareManager manager] shareFromViewController:weakSelf withInstance:weakSelf.shareInstance forSocialMedia:[weakSelf.shareCenterView socialMedia]];
                if ([weakSelf.shareCenterView socialMedia] == SocialMediaCopyURL) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakSelf appWillEnterForeGround: nil];
                    });
                }
            }];
            UIAlertAction *fileAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"library_share_weixin_with_file", @"分享到微信 文件形式 | 文件形式分享") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [weakSelf showDocumentInteraction];
            }];
            [alert addAction:linkAction];
            [alert addAction:fileAction];

            [weakSelf presentViewController:alert animated:YES completion:nil];
        }
        else {
            BOOL success = [[ShareManager manager] shareFromViewController:self withInstance:self.shareInstance forSocialMedia:[self.shareCenterView socialMedia]];
            if ([weakSelf.shareCenterView socialMedia] == SocialMediaCopyURL) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf appWillEnterForeGround: nil];
                });
            }
        }
    };

    shareBlock(self.uploadFile.mediaData.assetURLString);
}

- (void)uploadFailureWithReason:(UploadFailureReason)reason {
    [self invalidateTimer];
    self.isUploading = NO;
    if (reason == UploadFailureReasonCancelled) {
        return ;
    }

    self.btnShare.enabled = YES;
    [self resetProgressView];

    UIAlertController *alert = [BaseAutoLayout customAlertControllerWithTitle:NSLocalizedString(@"mine_upload_mission_cell_upload_failed_label", nil) message:nil preferredStyle:UIAlertControllerStyleAlert cancelTitle:NSLocalizedString(@"cancel", nil) sourceView:self.view];
    [self presentViewController:alert animated:YES completion:nil];
}

//重新设定  present动画相关属性
- (void)resetPresentProperties:(UIImageView*)fromView  {

    CGRect rect = [fromView convertRect:fromView.bounds toView:nil];
    CGSize imageSize = fromView.image.size;
    //处理 偏高 的视频 起始frame
    if (imageSize.height/imageSize.width > fromView.height/fromView.width) {
        CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        CGFloat width = rect.size.width;
        CGFloat height = width * imageSize.height/imageSize.width;
        self.presentFromRect = CGRectMake(center.x - width/2, center.y - height/2, width, height);
    }
    else {
        self.presentFromRect = rect;
    }
    UIImageView *imageView = [[UIImageView alloc] initWithImage:fromView.image];
    self.presentFromView = imageView;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = YES;

    //源自 DJIMoviePreviewVC 的setupPlayerViewWithVideo 方法
    CGFloat ratio = imageView.height / imageView.width;
    CGFloat sliderHeight = 15.;
    CGFloat viewHeight = SCREEN_WIDTH * ratio;
    CGFloat containerHeight = SCREEN_HEIGHT - self.headerHeight - 50;
    CGFloat offsetY = 0;
    if (viewHeight > containerHeight - 40) {
        viewHeight = containerHeight - 40;
        offsetY = 0;
    }else{
        if (viewHeight > containerHeight - 80) {
            offsetY = (containerHeight - viewHeight - sliderHeight) / 2;
        }else{
            offsetY = (containerHeight - viewHeight) / 2;
        }
    }
    self.presentToRect = CGRectMake(0, self.headerHeight + offsetY, SCREEN_WIDTH, viewHeight);

}

- (void)resetUploadReportParams {
    switch (self.shareCenterView.socialMedia) {
        case SocialMediaCopyURL:
            self.uploadFile.shareMedia = 8;
            break;
        case SocialMediaFacebook:
            self.uploadFile.shareMedia = 7;
            break;
        case SocialMediaTwitter:
            self.uploadFile.shareMedia = 99;
            break;
        case SocialMediaWhatsApp:
            self.uploadFile.shareMedia = 6;
            break;
        case SocialMediaInstagram:
            self.uploadFile.shareMedia = 5;
            break;
        case SocialMediaWeibo:
            self.uploadFile.shareMedia = 4;
            break;
        case SocialMediaQQ:
            self.uploadFile.shareMedia = 3;
            break;
        case SocialMediaWeChatSession:
            self.uploadFile.shareMedia = 1;
            break;
        case SocialMediaWeChatTimeline:
            self.uploadFile.shareMedia = 2;
            break;
            
        default:
            break;
    }
    
    
    self.uploadFile.deviceName = [self productClassOfShareItem];
    if([[RRBundleRedirect instance].currentLanguage hasPrefix:@"zh-Hans"]) {
        self.uploadFile.shareLanguage = 1;
    }
    else if([[RRBundleRedirect instance].currentLanguage hasPrefix:@"zh"]) {
        self.uploadFile.shareLanguage = 2;
    }
    else if ([[RRBundleRedirect instance].currentLanguage hasPrefix:@"ja"]) {
        self.uploadFile.shareLanguage = 4;
    } else if ([[RRBundleRedirect instance].currentLanguage hasPrefix: @"de"]) {
        self.uploadFile.shareLanguage = 5;
    } else if([[RRBundleRedirect instance].currentLanguage hasPrefix:@"ko"]){
        self.uploadFile.shareLanguage = 6;
    }
    else {
        self.uploadFile.shareLanguage = 3;
    }
    
    
    DJINetworkStatus networkStatus = [self.reachability  currentReachabilityStatus];
    if (networkStatus == DJIReachableViaWiFi) {
        self.uploadFile.network = 2;
    }
    else {
        self.uploadFile.network = 1;
    }
    //入口统计
    if (self.fromFPV) {
        self.uploadFile.shareSource = 6;
    }
    else if (self.fromMakeMovieVC) {
        self.uploadFile.shareSource = 2;
    }
    else if ([self.uploadFile.currentItem isKindOfClass:[CSegment class]] && ((CSegment*)self.uploadFile.currentItem).isQuickMovie) {
        
        self.uploadFile.shareSource = 7;
    }
}

- (NSString*)productClassOfShareItem {
    NSString *productClass = _useStaticProductClass?shareProductClass:nil;
    if (productClass) return productClass;
    
    productClass = self.uploadFile.mediaData.productClass;
    if (productClass) return productClass;
    
    //最后从 item里去取
    if ([self.uploadFile.currentItem isKindOfClass:[CSegment class]]) {
        return ((CSegment*)self.uploadFile.currentItem).productClass;
    }
    if ([self.uploadFile.currentItem isKindOfClass:[CDjiPhoto class]]) {
        return ((CDjiPhoto*)self.uploadFile.currentItem).productClass;
    }
    return nil;
}

#pragma mark --  序列帧 模式相关数据接口
- (UIImage*)thumbnailForFrames {
    return [UIImage imageWithContentsOfFile:[self localFrameImagePathAtIndex:0]];
}

- (NSString*)localFrameImagePathAtIndex:(NSInteger)index {
    if (index + 1 > self.framesImageCount) {
        return nil;
    }

    return [self.framesPathPrefix stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", @(index), self.framesFileSuffix]];
}

- (CGFloat)calculateProgressWithTask:(DJIMediaUploadTask*)task {
    if (task.state == DJIMediaUploadTaskState_Finished) {
        [_frameProgressDic setObject:@(1.0) forKey:@(task.taskId)];
    }
    else {
        [_frameProgressDic setObject:@(task.progress) forKey:@(task.taskId)];
    }

    CGFloat totalProgress = 0;
    for (NSNumber *progress in [_frameProgressDic allValues]) {
        totalProgress += [progress floatValue];
    }
    return totalProgress/(CGFloat)self.framesImageCount;
}

- (BOOL)isAllUploadTaskFinished {
    for (DJIMediaUploadTask *task in self.frameUploadTasks) {
        if (task.state != DJIMediaUploadTaskState_Finished) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Notification
- (void)appWillEnterForeGround: (NSNotification *)notification {
    if (!self.shouldJumpToProfile) {
        return ;
    }

    for (UIViewController* vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass: [DJIShareFinishVC class]]) {
            return ;
        }
    }
    //避免重复跳到 shareMore
    if ([self.navigationController.viewControllers.lastObject isKindOfClass:[DJIShareMoreVC class]]) {
        return;
    }

    [self saveContextToUserDefault];
    if (!self.fromFPV) {
        DJIShareMoreVC *shareMoreVC = [[DJIShareMoreVC alloc] initWithNibName:@"DJIShareMoreVC" bundle:nil];
        shareMoreVC.file = self.uploadFile;
        shareMoreVC.shareId = self.uploader.shareID;
        shareMoreVC.isVideo = (self.uploader.file.isPhoto == NO);
        shareMoreVC.shareInstance = self.shareInstance;
        [self.navigationController pushViewController: shareMoreVC animated: YES];

        //如果是 视频作品分享成功，将 flag设置一下
        [[DJIVideoProjectManager sharedProjectManager] setProjectIsUploadedWithFilePath:self.uploadFile.url.path uploadStatus:kDJIVideoProjectUploadStatusUploaded];
        [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareSuccess object:self.uploadFile.url.path];
        //序列帧分享成功， 清除 分享缓存
        [ShareManager removeFrameShareCache:self.segmentId];
    }
    else {  //回调告诉fpv 已分享成功，
        if (self.fpvShareCompletion) {
            self.fpvShareCompletion(self);
        }
    }
}

- (void)reachabilityDidChange: (NSNotification *)notification {
    if([[SettingManager sharedSettingManager] canUseNetworkToUpload] == NO && self.uploader != nil) {
        [[UploadManager sharedUploadManager] cancelUploadingForFile:self.uploadFile];
        self.uploader = nil;
        [self invalidateTimer];
        self.fakeProgress = 0.f;
        [self resetProgressView];
    }
}

- (void)twitterShareComplete: (NSNotification *)notification {
    NSDictionary *object = [notification object];
    BOOL success = [[object valueForKey:@"success"] boolValue];

    __weak typeof(self) weakSelf = self;
    void (^completeBlock)() = ^{
        if(success == NO) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }
        else {
            [weakSelf appWillEnterForeGround:nil];
        }
    };

    if([self.presentedViewController isKindOfClass:[SLComposeViewController class]]) {
        [self dismissViewControllerAnimated:YES completion:^{
            completeBlock();
        }];
    }
    else {
        completeBlock();
    }
}

- (void)shareSuccess:(NSNotification *)notification {
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self appWillEnterForeGround:nil];
    }];

}

#pragma mark - UploadTagSelectVCDelegate
- (void)uploadTagSelectVCDidSaved: (UploadTagSelectVC *)vc withTagsArray:(NSArray *)tagsArray {
    self.tagsArray = tagsArray;
    [self.navigationController popViewControllerAnimated: YES];
    [self reloadTagsView];
}

#pragma mark - DJIPulishArtWorkProgressViewDelegate
- (void)publishArtWorkProgressViewCancelUpload:(DJIPulishArtWorkProgressView*)progressView {
    [self OnCancelUpload];
}

- (void)publishArtWorkProgressViewFold:(DJIPulishArtWorkProgressView*)progressView {
    /*if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    else {
        self.btnShare.enabled = YES;
        [self.progressView hideProgressView];
     }*/
    if (self.fromFPV) { //FPV分享， 直接收起来，
        self.btnShare.enabled = YES;
        [self.progressView hideProgressView];
    }
    else {
        [[NSNotificationCenter defaultCenter] postNotificationName:DJIGO_Notification_ShareUploadingFold object:nil];
    }
}

#pragma mark - DJIShareCenterViewDelegate
- (void) shareCenterViewDidTap {
    [self.view endEditing: YES];
}

- (void)shareCenterViewDidTapShareMore {
    [self showDocumentInteraction];
}

#pragma mark -- UITextViewDelegate

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
    if (IS_IPAD) {
        [UIView animateWithDuration:.2 animations:^{
            self.view.frame = CGRectMake(0, -120, self.view.width, self.view.height);
        }];
        
    }
    return YES;
}
- (BOOL)textViewShouldEndEditing:(UITextView *)textView {
    if (IS_IPAD) {
        [UIView animateWithDuration:.2 animations:^{
            self.view.frame = CGRectMake(0, 0, self.view.width, self.view.height);
        }];
    }
    return YES;
}

#pragma mark - Touch Event
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self.titleField isFirstResponder]) {
        [Flurry djiLogEvent:@"v3_ed_video_share__title"];
    }
    [self.view endEditing: YES];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {

}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {

}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {

}

#pragma mark -- UIDocumentInteractionControllerDelegate

- (void)documentInteractionControllerDidDismissOptionsMenu:(UIDocumentInteractionController *)controller {
    //假设用户是分享成功了。 跳到分享结果界面
    [self appWillEnterForeGround: nil];
}

#pragma mark - DJISelectCoverVC
- (void)selectCoverVC:(DJISelectCoverVC *)selectVC didSelectCover:(UIImage *)coverImage {
    [self updateCoverWithImage: coverImage];

    [self dismissViewControllerAnimated: YES completion: nil];
    self.coverVC = nil;
}

- (void)selectCoverVCDidCancel:(DJISelectCoverVC *)selectVC {
    self.coverVC = nil;
}

@end
