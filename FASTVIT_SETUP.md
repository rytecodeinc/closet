# FastViT T8 Model Setup Instructions

The `VisionAnalysisService` has been updated to use Apple's FastViT T8 Core ML model for faster and more accurate image classification. Follow these steps to add the model to your project:

## Step 1: Download the FastViT T8 Model

1. Visit Apple's Machine Learning Models page: https://developer.apple.com/machine-learning/models/
2. Find the **FastViT** model section
3. Download **FastViTT8F16.mlpackage** (8.2MB) - this is the T8 variant optimized for speed
4. The download will be a ZIP file that extracts to a folder named `FastViTT8F16.mlpackage`

Alternatively, you can download directly:
- Direct download link: https://ml-assets.apple.com/coreml/models/Image/ImageClassification/FastViT/FastViTT8F16.mlpackage.zip

## Step 2: Add the Model to Your Xcode Project

1. **Extract the ZIP file** if needed (you should have a folder named `FastViTT8F16.mlpackage`)
2. **Open your Xcode project**
3. **Drag the `FastViTT8F16.mlpackage` folder** into your Xcode project
   - Drop it in the `closet` folder (same directory level as `Services`)
   - Or create a `Models` folder in `closet` and place it there
4. **In the "Choose options for adding these files" dialog:**
   - ✅ Check "Copy items if needed"
   - ✅ Select "Create groups" (not "Create folder references")
   - ✅ Make sure your app target (closet) is checked
   - Click "Finish"

## Step 3: Verify the Model is Added

1. The `FastViTT8F16.mlpackage` should appear in your Xcode project navigator
2. Select it and check the File Inspector (right panel)
3. Ensure it's included in your app target's "Target Membership"

## Step 4: Build and Test

1. Build your project (⌘B)
2. The code will automatically use FastViT if the model is found
3. If the model is not found, it will gracefully fall back to the built-in `VNClassifyImageRequest`

## Notes

- **Model Size**: The FastViT T8 model is 8.2MB, which is reasonable for app bundle size
- **Performance**: FastViT T8 provides faster inference (~0.52ms on iPhone 16 Pro) compared to the built-in classifier
- **Fallback**: The code automatically falls back to `VNClassifyImageRequest` if the model file is missing, so your app will still work without it
- **Model Location**: The code looks for the model at `Bundle.main.url(forResource: "FastViTT8F16", withExtension: "mlpackage")`, so make sure the filename matches exactly

## Troubleshooting

- **Model not found error**: Check that the filename is exactly `FastViTT8F16.mlpackage` (case-sensitive)
- **Build errors**: Ensure the `.mlpackage` folder is added as a group (blue folder icon), not a folder reference (yellow folder icon)
- **Model not loading**: Verify the model is included in your app target's build phases → Copy Bundle Resources



