
import Foundation
import UIKit
import AVFoundation

@MainActor
func getCurrentVc() -> UIViewController{
    let rootVc = UIApplication.shared.keyWindow?.rootViewController
    let currentVc = getCurrentVcFrom(rootVc!)
    return currentVc
}

@MainActor
func getCurrentVcFrom(_ rootVc:UIViewController) -> UIViewController{
   var currentVc:UIViewController
   var rootCtr = rootVc
   if(rootCtr.presentedViewController != nil) {
     rootCtr = rootVc.presentedViewController!
   }
   if rootVc.isKind(of:UITabBarController.classForCoder()) {
     currentVc = getCurrentVcFrom((rootVc as! UITabBarController).selectedViewController!)
   }else if rootVc.isKind(of:UINavigationController.classForCoder()){
      currentVc = getCurrentVcFrom((rootVc as! UINavigationController).visibleViewController!)
   }else{
     currentVc = rootCtr
   }
   return currentVc
}

@MainActor
func int16DataToPCMBuffer(int16Data: [Int16], sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioPCMBuffer? {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: false)
    let frameLength = UInt32(int16Data.count) / channels
    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat!, frameCapacity: frameLength) else {
        print("Can't creat AVAudioPCMBuffer")
        return nil
    }
    pcmBuffer.frameLength = frameLength
    if let channelData = pcmBuffer.int16ChannelData {
        for channel in 0..<Int(channels) {
            let channelPointer = channelData[channel]
            let samplesPerChannel = int16Data.count / Int(channels)
            for sampleIndex in 0..<samplesPerChannel {
                channelPointer[sampleIndex] = int16Data[sampleIndex * Int(channels) + channel]
            }
        }
    }
    return pcmBuffer
}

class EnlargedButton: UIButton {
    let touchAreaPadding: CGFloat = 15
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let largerFrame = bounds.insetBy(dx: -touchAreaPadding, dy: -touchAreaPadding)
        return largerFrame.contains(point)
    }
}
