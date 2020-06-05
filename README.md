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

Run any timeline_summary benchmark using the benchmark tools in the Flutter dev/devicelab
directory, and then:
```shell
pub global run flutter_benchmark_utils:graphTimeline test.timeline_summary.json
```
or with the pub global bin directory in your path:

```shell
graphTimeline test.timeline_summary.json
```

The script behaves analogously to the graphAB script in terms of launching a browser and
quitting.