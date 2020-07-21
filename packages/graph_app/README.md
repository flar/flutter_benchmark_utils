# graph_app

A Flutter sub-project for the Flutter Benchmark Tools containing a web app that can
graph the timeline results of Flutter benchmarks.

## Getting Started

This project is not normally visible if you open the Flutter Benchmark Tools project,
you will need to open it independently to contribute to it.

## Developing

While working on the graph_app web app you will want to test it by running it directly
from the source package rather than installing it each time you change it. You can use
a hidden command line option for the graphTimeline command `--web-local` that will
build the web app from this directory and then serve the results directly to the browser
from the build directory.

## Installing

When work is done on the graph_app, you should install it into the main part of the repo
so that it can be used by invocations activated using pub global. The `tools/install.sh`
shell script will clean and build the web app with the ClientKit option unless the `-n`
option is used and package the necessary run-time files into a zip file installed in the
`lib/src` directory of the main project. The install script should be executed from the
directory of the graph_app package or one of its direct sub-directories.

If you have added any dependencies that need to be served alongside the web app, you may
need to edit the install script as it contains a specific list of files needed to be
served to the browser at run time.
