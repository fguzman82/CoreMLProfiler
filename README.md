# CoreMLProfiler

<p align="center">
<img width="1274" alt="App_screenshot" src="https://github.com/fguzman82/CoreMLProfiler/assets/34175524/9818741e-752c-4736-950f-d3b30ac1613c">
</p>

## Overview

CoreMLProfiler is a macOS application designed to profile CoreML models. **It provides detailed estimates for each operation's time**, allowing users to view and filter results in a table. The application supports both `.mlpackage` and `.mlmodelc` formats and offers comprehensive insights into compilation, loading, and prediction times. Users can select different compute units and visualize performance metrics through an intuitive interface, with comprehensive statistics on all aspects of model profiling.

## Features

- Supports CoreML models in both `.mlpackage` and `.mlmodelc` (compiled models) formats.
- Profiles compilation, loading, and prediction times.
- Visualize the performance metrics through an intuitive interface.
- Sort the cost column to identify the most expensive operations.
- Option to export performance data to JSON.
- Test your models on different compute units like CPU, GPU, and Neural Engine.
- macOS native app using SwiftUI

## Compatibility

- Apple Silicon (M1 and later)
- macOS Sonoma 14.4 and later
- Xcode 15.2 and later (to build)
- dmg version ready to run in the [releases](https://github.com/fguzman82/CoreMLProfiler/releases) page. (it requires macos 14.4 or later)

## Installation
You can download the app from releases or build the project.

### Releases

Download the latest version (dmg file) from the [releases](https://github.com/fguzman82/CoreMLProfiler/releases) page

### Build the project

If you want to build the project, follow these steps (requires Xcode 15.2 or later).

1. Clone the repository:
    ```sh
    git clone https://github.com/yourusername/CoreMLProfiler.git
    ```

2. Open the project in Xcode:
    ```sh
    cd CoreMLProfiler
    open CoreMLProfiler.xcodeproj
    ```

3. Build and run the project in Xcode.





## Usage

1. Launch CoreMLProfiler.
2. Select the processing units (CPU, GPU, Neural Engine) from the UI.
3. Load a CoreML model file (`.mlpackage` or `.mlmodelc`).
4. View detailed profiling data for compilation, loading, and prediction times.
5. Optionally, enable full profiling mode for more granular insights.
6. Export the performance data to a JSON file for further analysis.

## Models

You can test CoreMLProfiler with your own models or download models from the CoreML community on Hugging Face. [here](https://huggingface.co/coreml-community).

## CoreML Profiler Details

The heart of CoreML Profiler consists of two main components: 1) utilizing the MLComputePlan() class from the CoreML Framework, which allows the extraction of costs for each operation of the model, and 2) a prediction function that uses a dummy input, automatically created according to the data structure reported in the CoreML Package.

### Supported Structures
Here are the data structures that can be automatically generated as dummy inputs to test the prediction function and estimate prediction times:

- MultiArray
- Int64
- Double
- String
- Dictionary
- Image
- Sequence

### Operation Details of the Profiler

The selected mlpackage file is first compiled to generate the compiled mlmodelc model. Then, `loadModel` is executed with the selected processing units (CPU, GPU, Neural Engine). The input types supported by the model are inspected to launch the `createDummyInput` function, which emulates random data according to the input type. With this input, the model prediction is executed to estimate prediction times and compute the duration of each operation extracted from MLComputePlan.

The compilation, load, and predict processes are repeated several times to collect statistics on the times to report them in the profile visualization.

When the file is already compiled (type mlmodelc), the compilation process is skipped, and the remaining steps described above are performed.

### Full Profile

The Full Profile option (enabled by default) is in Beta. This option enables creating dummy input and performing the prediction. When this option is disabled, only the cost of each operation is computed, and execution times are not estimated.

### Log Terminal

A log terminal is included to monitor the profiling flow and visualize errors if any.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request or open an Issue to discuss changes or improvements.

## License

CoreMLProfiler is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Contact

For any questions or inquiries, please contact Fabio Guzman at fabioandres.guzman@gmail.com.

## Release Notes

### v0.1

- Initial release of CoreMLProfiler.
- Support for profiling CoreML models in `.mlpackage` and `.mlmodelc` formats.
- Detailed performance metrics for compilation, loading, and prediction.
- Option to export performance data to JSON.
