//
//  CropImageView.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@available(iOS 14.0, macOS 11, *)
public struct CropImageView: View {
    @Binding var isPresented: Bool
    var inputImage: UnifiedImage
    var desiredAspectRatio: CGFloat
    var cancelPressed: () -> Void
    var onCompletion: (UnifiedImage) -> Void

    public init(
        _ isPresented: Binding<Bool>,
        inputImage: UnifiedImage,
        desiredAspectRatio: CGFloat,
        cancelPressed: @escaping () -> Void,
        onCompletion: @escaping (UnifiedImage) -> Void
    ) {
        self._isPresented = isPresented
        self.inputImage = inputImage
        self.desiredAspectRatio = 1 / desiredAspectRatio
        self.cancelPressed = cancelPressed
        self.onCompletion = onCompletion
    }

    @State private var imageAspectRatio: CGFloat = 0.0
    @State private var displayWidth: CGFloat = 0.0
    @State private var displayHeight: CGFloat = 0.0
    @State private var screenSize: CGSize = .zero
    @State private var screenAspectRatio: CGFloat = 0.0
    @State private var isDraggingImage: Bool = false
    let inset: CGFloat = 20
   
    //Zoom Scale and Drag...
    @State private var currentScaleAmount: CGFloat = 0
    @State private var finalScaleAmount: CGFloat = 1
    @State private var minScaleAmount: CGFloat = 1
    @State private var currentPosition: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var imageViewSize: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0.0
    @State private var verticalOffset: CGFloat = 0.0
    
    public var body: some View {
        contents
            .readViewSize(onChange: setScreenParticulars(_:))
    }
    
    var contents: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(unifiedImage: inputImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .readViewSize(onChange: setImageViewSize(_:))
                        .scaleEffect(finalScaleAmount + currentScaleAmount)
                        .offset(x: self.currentPosition.width, y: self.currentPosition.height)
                        
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            
            Rectangle()
                .fill(Color.black.opacity(isDraggingImage ? 0.3 : 0.8))
                .mask(
                    HoleShapeMask(screenSize: screenSize, inset: inset, desiredAspectRatio: desiredAspectRatio)
                        .fill(style: FillStyle(eoFill: true))
                 )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            WhiteGridOverlay(screenSize: screenSize, inset: inset, desiredAspectRatio: desiredAspectRatio)
            cropImageViewOverlay
        }
        .gesture(magGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    var cropImageViewOverlay: some View {
        VStack {
            HStack {
                EditorControlButton("xmark.circle", action: closeCancelAction)
                Spacer()
                Text("Move and Scale")
                Spacer()
                EditorControlButton("checkmark.circle", action: cropImage)
            }
            .padding(.top)
            .opacity(isDraggingImage ? 0 : 1)
            Spacer()
            bottomButtons
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white)
        .padding(.horizontal)
    }
    
    var bottomButtons: some View {
        HStack {
            Spacer()
            #if os(macOS)
            HStack {
                Slider(value: $finalScaleAmount, in: 1...5, label: {
                    Text("Scale: \(Int(finalScaleAmount * 100/5))%")
                }, minimumValueLabel: {
                    Text("min")
                }, maximumValueLabel: {
                    Text("max")
                }, onEditingChanged: { isEd in
                    if !isEd {
                        repositionImage()
                    }
                })
                .frame(width: 250)
            }
            #endif
            Spacer()
        }
        .padding(10)
    }
    
    var magGesture: some Gesture {
        MagnificationGesture()
            .onChanged { amount in
                setIsDraggingImage(to: true)
                self.currentScaleAmount = amount - 1
            }
            .onEnded { amount in
                setIsDraggingImage(to: false)
                self.finalScaleAmount += self.currentScaleAmount
                self.currentScaleAmount = 0
                repositionImage()
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                setIsDraggingImage(to: true)
                self.currentPosition = CGSize(
                    width: value.translation.width + self.newPosition.width,
                    height: value.translation.height + self.newPosition.height
                )
            }
            .onEnded { value in
                setIsDraggingImage(to: false)
                self.currentPosition = CGSize(
                    width: value.translation.width + self.newPosition.width,
                    height: value.translation.height + self.newPosition.height
                )
                self.newPosition = self.currentPosition
                repositionImage()
            }
    }
    
    var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                resetImageOriginAndScale()
            }
    }
    
    private func setImageViewSize(_ size: CGSize) {
        imageViewSize = size
        print("Image View", size)
        scaleImagetoFit()
    }
    
    private func setScreenParticulars(_ size: CGSize) {
        screenSize = size
        screenAspectRatio = size.width / size.height
        let w = inputImage.size.width
        let h = inputImage.size.height
        imageAspectRatio = w / h
        resetImageOriginAndScale()
        print("Screen size", screenSize)
        scaleImagetoFit()
    }

    private func closeCancelAction() {
        withAnimation {
            isPresented = false
        }
    }
    
    private func resetImageOriginAndScale() {
        withAnimation(.easeInOut) {
            currentScaleAmount = 0
            finalScaleAmount = minScaleAmount
            currentPosition = .zero
            newPosition = .zero
        }
    }
    
    private var holeWidth: CGFloat {
        screenSize.width - (inset * 2)
    }
    
    private var holeHeight: CGFloat {
        holeWidth * desiredAspectRatio
    }
    
    private func scaleImagetoFit() {
        guard imageViewSize != .zero else {
            return
        }
        let widthScaleFactor = holeWidth / imageViewSize.width
        let heightScaleFactor = holeHeight / imageViewSize.height
        
        if imageViewSize.height < holeHeight {
            finalScaleAmount = heightScaleFactor
            minScaleAmount = heightScaleFactor
        } else if imageViewSize.width < holeWidth {
            finalScaleAmount = widthScaleFactor
            minScaleAmount = widthScaleFactor
        } else {
            minScaleAmount = max(heightScaleFactor, widthScaleFactor)
        }
    }
    
    private func repositionImage() {
        if finalScaleAmount > 10.0 {
            withAnimation(.spring()) {
                finalScaleAmount = 10.0
            }
        }
        
        if finalScaleAmount < minScaleAmount {
            withAnimation(.spring()) {
                finalScaleAmount = minScaleAmount
            }
        }
        
        let heightOffsetLimit = (imageViewSize.height / 2 * finalScaleAmount) - (holeHeight / 2)
        let widthOffsetLimit = (imageViewSize.width / 2 * finalScaleAmount) - (holeWidth / 2)
        
        // Leading
        if currentPosition.width > widthOffsetLimit {
            withAnimation(.easeInOut) {
                currentPosition.width = widthOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Trailing
        if currentPosition.width < -widthOffsetLimit {
            withAnimation(.easeInOut) {
                currentPosition.width = -widthOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Top
        if currentPosition.height > heightOffsetLimit {
            withAnimation(.easeInOut) {
                currentPosition.height = heightOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Bottom
        if currentPosition.height < -heightOffsetLimit {
            withAnimation(.easeInOut) {
                currentPosition.height = -heightOffsetLimit
                newPosition = currentPosition
            }
        }
    }

    private func setIsDraggingImage(to bool: Bool) {
        withAnimation(.spring()) {
            isDraggingImage = bool
        }
    }

    private func cropImage() {
        let scale = (inputImage.size.width) / displayWidth
        let xPos = ( ( ( displayWidth - screenSize.width ) / 2 ) + inset + ( currentPosition.width * -1 ) ) * scale
        let yPos = ( ( ( displayHeight - (screenSize.width * desiredAspectRatio) ) / 2  ) + inset + ( currentPosition.height * -1 ) ) * scale
        let radius = ( screenSize.width - inset * 2 ) * scale
        let radius1 = radius * desiredAspectRatio
        guard let img = imageFromCrop(image: inputImage, croppedTo: CGRect(x: xPos, y: yPos, width: radius, height: radius1)) else {
            // Err callback
            isPresented = false
            return
        }
        onCompletion(img)
        isPresented = false
    }
    
    #if os(iOS)
    private func imageFromCrop(image: UIImage, croppedTo rect: CGRect) -> UIImage? {
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        let drawRect = CGRect(x: -rect.origin.x, y: -rect.origin.y, width: image.size.width, height: image.size.height)
        context?.clip(to: CGRect(x: 0, y: 0, width: rect.size.width, height: rect.size.height))
        image.draw(in: drawRect)
        let subImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return subImage
     }
    #else

    private func imageFromCrop(image: NSImage, croppedTo rect: CGRect) -> NSImage? {
        let croppedImrect: CGRect = rect
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        var croppedImage = NSImage(named: "iconWhite")
        if let cropped = cgImage!.cropping(to: croppedImrect) {
            croppedImage = NSImage(cgImage: cropped, size: rect.size)
        }
        return croppedImage
    }
    #endif
}

@available(iOS 14.0, macOS 11, *)
public struct Croppr: View {
    
    public init(){}
    
    public var body: some View {
//        Image("mac")
//            .resizable()
//            .frame(width: 400, height: 400)
        CropImageView(
            .constant(true),
            inputImage: UnifiedImage(named: "sunflower")!,
            desiredAspectRatio: 16/9,
            cancelPressed: {},
            onCompletion: { img in
                
            }
        )
    }
}

//@available(iOS 14.0, macOS 11, *)
//struct Cropr_Previews: PreviewProvider {
//    static var previews: some View {
//        ImageEditor(
//            image: .constant(UnifiedImage(named: "mac")!),
//            aspectRatio: 1,
//            onCompletion: { img in
//
//            }
//        )
//        CropImageView(
//            .constant(true),
//            inputImage: UnifiedImage(named: "mac")!,
//            desiredAspectRatio: 16/9,
//            cancelPressed: {},
//            onCompletion: { img in
//
//            }
//        )
//    }
//}
