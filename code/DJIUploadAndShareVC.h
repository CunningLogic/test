//
//  DJIUploadAndShareVC1.h
//  Phantom3
//
//  Created by pygzx on 15/8/24.
//  Copyright (c) 2015年 DJIDevelopers.com. All rights reserved.
//

#import "SkinViewController.h"

@class UploadFile;
@class DJIUploadAndShareVC1;
@class DJIVideoEditProject;

@interface DJIUploadAndShareVC1 : SkinViewController


- (id) initWithFile:(UploadFile*)file;
- (id) initWithFileAndProductClass:(UploadFile*)file;   //表示从 setShareProductClass 里取 分享的视频拍摄的设备
- (id) initWithFile:(UploadFile*)file withVideoProject: (DJIVideoEditProject*)project;
//序列帧需求
/*******
 传入 一系列图片的路径。
 pathPrefix：图片的路径前缀目录。
 suffix: 图片文件的后缀
 imageCount：图片个数。 图片完整路径拼凑： pathPrefix/0.jpg  pathPrefix/1.jpg ......
 musicId: BGM id， 用MusicManager 去取 music 路径
 segmentId: 唯一标示 序列帧 源视频，主要是存储 未分享的序列帧工程
 *********/
- (id) initWithImageFrames:(NSString*)pathPrefix
                    suffix:(NSString*)suffix
                imageCount:(NSInteger)imageCount
                   musicId:(NSInteger)musicId
                 segmentId:(NSString*)segmentId;

+ (void)setShareProductClass:(NSString*)productClass;

@property (nonatomic, assign) BOOL fromMakeMovieVC;

- (void)updateCoverWithImage:(UIImage*)image;

/********  初始化后的部分 参数设置 ************/
@property (nonatomic, assign) BOOL  fromFPV; //fpv 专用, 强制设置 横屏模式, 且分享后不跳入shareMore，直接调block
@property (nonatomic, copy)     void(^fpvShareCompletion)(DJIUploadAndShareVC1*);    //分享完成block；由外面决定是否dismiss，
@property (nonatomic, assign)   UIInterfaceOrientation  orientationOfFPV;   //记录FPV的 转向，share界面转向跟它一样

@property (nonatomic, strong) NSString  *assetUrl; //上级界面直接保存到相册后，设置该值（主要用于 instgram 分享)

//续传 部分设置参数
@property (nonatomic, assign) BOOL  autoUpload; //打开页面后，自动开始上传 or  续传
@property (nonatomic, assign) CGFloat  autoUploadResumeProgress; //打开页面后，自动开始上传 or  续传  的开始进度

//动画相关的 frame保存
@property (nonatomic, assign) CGRect presentFromRect;
@property (nonatomic, assign) CGRect presentToRect;
@property (nonatomic, strong) UIView    *presentFromView;

@end
