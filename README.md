# ostrich

This package is designed to be a drop-in replacement for a dart based server in a docker image on cloud run for example. This package allows you to get the flutter sdk as we're effectively running a flutter app on the server in docker.

Instead of 

```dart
void main() async {
  // Do server start
}
```

```dart
void main() => runFlutterServer((context) async {
  // Do server start
});
```

# Benefits
* You can now use the dart:ui package
* A lot of packages on pub.dev are flutter packages. PDF rendering can now be done with the [pdf](https://pub.dev/packages/pdf) package.
* You can now render via canvas and PictureRecorder
* You can use any flutter packages with native plugins that support linux (or whatever platform your using if not docker linux)

# Setup (Docker)
```Dockerfile
# Build the Server
FROM --platform=linux/amd64 dart:stable AS server-builder
ENV FLUTTER_HOME=/flutter
ENV PATH=$FLUTTER_HOME/bin:$PATH

# Install tools required to run flutter & media libraries
RUN apt-get update && apt-get install -y \
    curl git unzip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* 

# Clone & Install Flutter
RUN git clone https://github.com/flutter/flutter.git $FLUTTER_HOME && \
    flutter channel stable && \
    flutter upgrade --force

# Build the project
WORKDIR /app
COPY pubspec.* ./
COPY . .
RUN flutter pub get
RUN flutter build linux --release

# Server Runtime
FROM --platform=linux/amd64 dart:stable
RUN apt-get update && apt-get install -y \
    wget \
    xvfb \
    libgtk-3-0 \
    libegl1 \
    libgles2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* 

# Install built libraries into final image
RUN ldconfig
WORKDIR /app
COPY --from=server-builder /app/build/linux/x64/release/bundle ./bundle

# You can also make this docker image act as if it were running in GCP
# So you can use all the Google Cloud libraries in a dev environment
# But only add this if your in a dev environment as GCP automatically
# Adds these to the environment. 
### DEV ONLY NOT FOR GCP ###################################################
COPY my-gcp-svc-acct-key.json ./ 
ENV GOOGLE_APPLICATION_CREDENTIALS=/app/my-gcp-svc-acct-key.json
ENV GCP_PROJECT=my-gcp-project-id
############################################################################

# Link libraries to LD path so they are visible on linux
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/usr/lib:

# Find the server executable
RUN find ./bundle -type f -executable ! -name "*.so" -printf "%f\n" > executable_name.txt
EXPOSE 8080

# Run the flutter server with xvfb to simulate a display
CMD xvfb-run -a ./bundle/$(cat executable_name.txt)
```

# Setup (Docker with ImageMagick via FFI)
If you want to use the [multimedia](https://pub.dev/packages/multimedia) package to convert / edit images, we can build a fresh copy of imagemagick and link it to our executable.

1. Add the multimedia package with `flutter pub add multimedia`
2. Add [libimage_magick_ffi.so](https://github.com/ArcaneArts/multimedia/blob/main/lib/libraries/libimage_magick_ffi.so) to your project (if its my_server/lib), then place this file in (my_server/ffi/libimage_magick_ffi.so).
3. Change startup code to load the library
    ```dart
    import 'package:ostrich/ostrich.dart';
    import 'package:multimedia/multimedia.dart';
    
    void main() {
      Future<void> imageMagickLoader = initMultimedia(
        overrideLibrary: File("/app/./bundle/libimage_magick_ffi.so"),
      );
      return runFlutterServer((context) async {
        // You don't need to wait for imageMagickLoader to complete
        // You just need to wait for it to complete before you try
        // to use any multimedia functionality
        await imageMagickLoader; 
        // Do server start
        
        // Do image stuff
        await MediaPipeline([
          MagickImageLoaderJob(File("in.png")),
          ImageOptimizerWebPJob(output: File("image.webp"), maxDimension: 4096, maxBytes: 300 * _kb),
          ImageOptimizerWebPJob(output: File("thumb.webp"), maxDimension: 256, maxBytes: 3 * _kb),
          ImageScaleWebPJob(output: File("low.webp"), maxDimension: 512, quality: 15),
          ImageThumbHashJob(onThumbHash: (h) => th = h),
        ]).push();
      });
    }
    ```
   
4. Define a docker file which builds imagemagick & your server and links it all (uncached builds can take 20+ minutes beware your compiling all image libraries from source)
   
   ```Dockerfile
   # Build the Server
   FROM --platform=linux/amd64 dart:stable AS server-builder
   ENV FLUTTER_HOME=/flutter
   ENV PATH=$FLUTTER_HOME/bin:$PATH
   
   # Install tools required to run flutter & media libraries
   RUN apt-get update && apt-get install -y \
       curl git unzip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev \
       && apt-get clean \
       && rm -rf /var/lib/apt/lists/* 
   
   # Clone & Install Flutter
   RUN git clone https://github.com/flutter/flutter.git $FLUTTER_HOME && \
       flutter channel stable && \
       flutter upgrade --force
   
   # Build the project
   WORKDIR /app
   COPY pubspec.* ./
   COPY . .
   RUN flutter pub get
   RUN flutter build linux --release
   
   # Image Magick Capabilities
   FROM --platform=linux/amd64 debian:bullseye-slim AS imagemagick-builder
   
   # Install tools required to compile libraries for linux
   RUN apt-get update && apt-get install -y \
       build-essential \
       wget \
       libltdl-dev \
       libpng-dev \
       libjpeg-dev \
       libtiff-dev \
       libjbig-dev \
       libgomp1 \
       pkg-config \
       && apt-get clean \
       && rm -rf /var/lib/apt/lists/* 
   
   # Compile ImageMackgic & Libraries
   WORKDIR /tmp
   RUN wget https://github.com/webmproject/libwebp/archive/refs/tags/v1.4.0.tar.gz \
       && tar xvzf v1.4.0.tar.gz \
       && cd libwebp-1.4.0 \
       && ./autogen.sh \
       && ./configure \
       && make \
       && make install \
       && wget https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.1-39.tar.gz \
       && tar xvzf 7.1.1-39.tar.gz \
       && cd ImageMagick-7.1.1-39 \
       && ./configure --disable-hdri --with-quantum-depth=8 --with-png=yes --with-webp=yes --with-jpeg=yes \
       --with-jp2=yes --without-tiff --with-modules --enable-shared \
       && make \
       && make install 
   
   # Server Runtime
   FROM --platform=linux/amd64 dart:stable
   RUN apt-get update && apt-get install -y \
       wget \
       libltdl-dev \
       libpng-dev \
       libjpeg-dev \
       libtiff-dev \
       libjbig-dev \
       libgomp1 \
       xvfb \
       libgtk-3-0 \
       libegl1 \
       libgles2 \
       && apt-get clean \
       && rm -rf /var/lib/apt/lists/* 
   
   # Install built libraries into final image
   COPY --from=imagemagick-builder /usr/local /usr/local
   RUN ldconfig
   WORKDIR /app
   COPY --from=server-builder /app/build/linux/x64/release/bundle ./bundle
   COPY --from=server-builder /app/ffi/libimage_magick_ffi.so ./bundle
   
   # You can also make this docker image act as if it were running in GCP
   # So you can use all the Google Cloud libraries in a dev environment
   # But only add this if your in a dev environment as GCP automatically
   # Adds these to the environment. 
   ### DEV ONLY NOT FOR GCP ###################################################
   COPY my-gcp-svc-acct-key.json ./ 
   ENV GOOGLE_APPLICATION_CREDENTIALS=/app/my-gcp-svc-acct-key.json
   ENV GCP_PROJECT=my-gcp-project-id
   ############################################################################
   
   # Link libraries to LD path so they are visible on linux
   ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/usr/lib:
   
   # Find the server executable
   RUN find ./bundle -type f -executable ! -name "*.so" -printf "%f\n" > executable_name.txt
   EXPOSE 8080
   
   # Run the flutter server with xvfb to simulate a display
   CMD xvfb-run -a ./bundle/$(cat executable_name.txt)
   ```