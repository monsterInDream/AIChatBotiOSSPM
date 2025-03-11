
import UIKit
import AVFoundation

class RecordAudioManager: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable{

    var audioUnit: AudioUnit?
    var local_record_buffers = [AVAudioPCMBuffer]()
    var local_record_Array = [[String: Any]]()
    
    static let shared = RecordAudioManager()
    private override init(){
        super.init()
    }
    
    //MARK: 1.Start collecting audio data.
    func startRecordAudio(){
        if let audioUnit1 = audioUnit{
            let error = AudioOutputUnitStart(audioUnit1)
            if error == noErr{
                print("Start Audio Unit--Success")
            }else{
                print("Start Audio Unit--fail:\(error)")
            }
            return
        }
        //0.1.Check microphone permission.：
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("The user denies microphone permission.")
            }else{
                print("The user has already granted microphone permission.")
            }
        }
        //0.2.Set up the session.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            //try audioSession.setCategory("AVAudioSessionCategoryPlayAndRecord", mode: "AVAudioSessionModeDefault", options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            print("Set up AVAudioSession1 success")
        } catch {
            print("Set up AVAudioSession1 fail: \(error)")
        }
        //1.Initialize.
        var audioComponentDesc = AudioComponentDescription()
        //1.1AudioUnits are categorized into the following types：
        audioComponentDesc.componentType = kAudioUnitType_Output
        audioComponentDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO//Echo cancellation mode
        audioComponentDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        audioComponentDesc.componentFlags = 0
        audioComponentDesc.componentFlagsMask = 0
        
        //2.Create an audio unit：
        guard let audioComponent = AudioComponentFindNext(nil, &audioComponentDesc) else {
            print("Failed to find Audio Unit")
            return
        }
        AudioComponentInstanceNew(audioComponent, &audioUnit)
        guard let audioUnit = audioUnit else {
            print("Failed to create Audio Unit instance")
            return
        }
        
        //3.Set the input pipeline.
        var enableIO: UInt32 = 1
        let status_input = AudioUnitSetProperty(audioUnit,
                                                kAudioOutputUnitProperty_EnableIO,
                                                kAudioUnitScope_Input,
                                                1,
                                                &enableIO,
                                                UInt32(MemoryLayout.size(ofValue: enableIO)))
        //MUST---mSampleRate: 24000
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 24000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        AudioUnitSetProperty(audioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             1, // 输入bus
                             &audioFormat,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        //3.3.Enable input callback.
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        AudioUnitSetProperty(audioUnit,
                             kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global,
                             1,
                             &inputCallbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        
        //4.Set the output pipeline.
        var enable_out: UInt32 = 0
        let status_output = AudioUnitSetProperty(audioUnit,
                                                 kAudioOutputUnitProperty_EnableIO,
                                                 kAudioUnitScope_Output,
                                                 0,
                                                 &enable_out,
                                                 UInt32(MemoryLayout.size(ofValue: enable_out)))
        //5.
        let error = AudioOutputUnitStart(audioUnit)
        if error == noErr{
            print("Start Audio Unit--Success")
        }else{
            print("Start Audio Unit--fail:\(error)")
        }
       
    }
    //MARK: 2.Process the collected audio data.
    private static let bufferListLock = NSLock()
    var count  = 0
    let inputRenderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: inNumberFrames * 2,
                mData: UnsafeMutableRawPointer.allocate(byteCount: Int(inNumberFrames) * 2, alignment: MemoryLayout<Int16>.alignment)
            )
        )
        let status = AudioUnitRender(RecordAudioManager.shared.audioUnit!,
                                     ioActionFlags,
                                     inTimeStamp,
                                     inBusNumber,
                                     inNumberFrames,
                                     &bufferList)
        if status == noErr {
            
            RecordAudioManager.bufferListLock.lock()
            let inputData = bufferList.mBuffers.mData?.assumingMemoryBound(to: Int16.self)
            let frameCount = Int(inNumberFrames)
            var int16_array: [Int16] = []
            for frame in 0..<frameCount {
                let sample = inputData?[frame] ?? 0
                int16_array.append(sample)
            }
            
            var rmsValue: Float = 0.0
            for frame in 0..<frameCount {
                let sample = inputData?[frame] ?? 0
                int16_array.append(sample)
                let normalizedSample = Float(sample) / Float(Int16.max)
                rmsValue += normalizedSample * normalizedSample
            }
            rmsValue = sqrt(rmsValue / Float(frameCount))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "showMonitorAudioDataView"), object: ["rmsValue": Float(rmsValue)])
            }
            RecordAudioManager.bufferListLock.unlock()
            
            DispatchQueue.main.async {
                if let buffer = int16DataToPCMBuffer(int16Data: int16_array, sampleRate: Double(44100), channels: 1){
                    RecordAudioManager.shared.local_record_buffers.append(buffer)
                }
                //[int16]-->Data
                let pcmData = Data(bytes: int16_array, count: int16_array.count * MemoryLayout<Int16>.size)
                //Data-->Base64String
                let data_base64 = pcmData.base64EncodedString()
                //Send Message
                var current_audio_data = [String: Any]()
                current_audio_data["type"] = "input_audio_buffer.append"
                current_audio_data["audio"] = data_base64
                current_audio_data["sequenceNumber"] = Int(RecordAudioManager.shared.count)
                RecordAudioManager.shared.local_record_Array.append(current_audio_data)
                if RecordAudioManager.shared.count == 0 || RecordAudioManager.shared.local_record_Array.count == 1{
                    RecordAudioManager.shared.sendMessageOneByOne()
                   
                }
                RecordAudioManager.shared.count += 1
            }
            
        } else {
            print("AudioUnitRender failed with status: \(status)")
        }
        return noErr
    }
    func sendMessageOneByOne(){
        if self.local_record_Array.count <= 0{
            return
        }
        let firstEventInfo = self.local_record_Array[0]
        if let sequenceNumber = firstEventInfo["sequenceNumber"] as? Int,
           let audio = firstEventInfo["audio"] as? String,
           let type = firstEventInfo["type"] as? String{
            let event: [String: Any] = [
                "type": type,
                "audio": audio
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8){
                WebSocketManager.shared.socket.write(string: jsonString) {
                    if self.local_record_Array.count > 0{
                        self.local_record_Array.removeFirst()
                        self.sendMessageOneByOne()
                        //print("send message success---\(sequenceNumber)")
                    }
                }
            }
        }
    }
    //MARK: 3.Stop the collected audio data.
    func stopCollectedAudioData(){
        guard let audioUnit = audioUnit else {
            print("Failed to create Audio Unit instance")
            return
        }
        if AudioOutputUnitStop(audioUnit) == noErr {
            print("Audio Unit Stopped - Success")
        } else {
            print("Audio Unit Stop - Fail")
        }
        self.local_record_buffers.removeAll()
        print("Cleared local_record_buffers")
        self.local_record_Array.removeAll()
        print("Cleared local_record_Array")
        self.count = 0
        print("Reset count to 0")
    }
}
