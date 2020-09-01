# flutter_benchmark_utils

Flutter package with scripts to graph and analyze Flutter benchmark output

Currently the package exports the following executables:
- graphAB --[no-]launch [ <ABresults.json files> ]
- graphTimeline --[no-]launch [ <test.timeline_summary.json files> ]

# Install

First install [dart](https://dart.dev/get-dart), and
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).
Make sure that `pub` and `git` are on your path.

For maximum ease of use, make sure the appropriate pub global bin directory
is on your path, this lets you run the commands above directly from the
[command line](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).

Then run:
```shell
pub global activate -sgit http://github.com/flar/flutter_benchmark_utils
```

# Run

## graphAB

Run an AB benchmark using the benchmark tools in the Flutter dev/devicelab directory,
and then:
```shell
pub global run flutter_benchmark_utils:graphAB ABresults.json
```

or if you have included the pub global bin directory in your path:

```shell
graphAB ABresults.json
```

Including multiple JSON files on the command line will create multiple URLs which can be
opened into multiple web pages.

The script will provide one or more URLs to click on to view the graphs, or you can use
the `--launch` command line option to immediately launch the web page in the system default
browser. Typing 'l' after the executable is running will also (re)launch the web pages in the
default browser.

The executable will continue to run and host the URLs until you type `q` to quit it.

## graphTimeline

Run any timeline_summary benchmark using the benchmark tools in the Flutter dev/devicelab
directory, and then:
```shell
pub global run flutter_benchmark_utils:graphTimeline test.timeline_summary.json
```
or with the pub global bin directory in your path:

```shell
graphTimeline test.timeline_summary.json [--web]
```

The script behaves analogously to the graphAB script in terms of launching a browser and
quitting.

The `graphTimeline` script also has the additional benefit of a Flutter web implementation
that is expanded over the basic graphing mechanism. The web app implementation is now the
default, but you can still specify `--no-web` on the command line to use the old plain
JavaScript mechanism. The web version improves upon the original by opening only
a single page to view multiple timeline files, switchable using a drop-down menu item in
the title bar, and it also supports graphing from raw event timeline files - allowing you
to graph any of the event streams in the file, not just the frame Build and Render timings.

## graphDashboard

An alternative graphing of the go/flutter-dashboard benchmark dashboard can be launched
using the command:

```shell
pub global run flutter_benchmark_utils:graphDashboard
```
or with the pub global bin directory in your path:

```shell
graphDashboard
```

This version of the dashboard has a number of additional filtering tools that can be
accessed using the "sort by" icon in the upper right of the page as well as scrollable
timeline histories for individual benchmarks if you double click on the benchmark tile.

There are also tiles that show all 4 "build time" or "rasterizer time" metrics overlaid
into a single graph.

The benchmark histories can also navigate forward/back by a single commit if you click
on the graph to lock in a result and then use the navigation arrows next to the commit
and creation date below the graph.

There are 2 sliders that allow you to slide the window back and forth (the slider with
a single thumb) or to change the size of the window (the slider with two thumbs).
