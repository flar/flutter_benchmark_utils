# flutter_benchmark_utils

Flutter package with scripts to graph and analyze Flutter benchmark output

Currently the package exports the following executables:
- graphAB --[no-]launch <ABresults.json file>

# Install

First install [dart](https://dart.dev/get-dart), and
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).
Make sure that `pub` and `git` are on your path.

Then run:
```shell
pub global activate -sgit http://github.com/flar/flutter_benchmark_utils
```

# Run
Run an AB benchmark using the benchmark tools in the Flutter dev/devicelab diretory, and then
```shell
pub global run flutter_benchmark_utils:graphAB ABresults.json
```

The script will provide a URL to click on to view the graphs, or you can use the `--launch`
option to just launch the web page in the system default browser.

The executable will continue to run and host the URL until you type `q` to quit it.
