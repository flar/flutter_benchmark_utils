function makeDiv(id, style) {
  var div = document.createElement('div');
  div.id = id;
  div.style = style;
  for (var i = 2; i < arguments.length; i++) {
    div.appendChild(arguments[i]);
  }
  return div;
}

function makeButton(text, onclick) {
  var button = document.createElement('button');
  button.innerHTML = text;
  button.onclick = onclick;
  return button;
}

function loadJSON() {
  var input = document.getElementById('file-input');
  if (input.files.length > 0) {
    var fileReader = new FileReader();
    fileReader.onload = function(e) {
      var filename = input.files[0].name;
      var data = jQuery.parseJSON(fileReader.result);
      replaceResults(data, filename);
    };
    console.log('reading '+input.files[0]);
    fileReader.readAsText(input.files[0]);
  }
}

function stripStringEnd(str, suffix) {
  if (suffix && str.endsWith(suffix)) {
    str = str.substring(0, str.length - suffix.length);
  }
  return str;
}

additional_json_suffix = null;

function stripJsonSuffix(str) {
  return stripStringEnd(stripStringEnd(str, '.json'), additional_json_suffix);
}

function lastPathName(str) {
  var index = str.lastIndexOf('/');
  if (index >= 0) {
    str = str.substring(index + 1);
  }
  return str;
}

function sourceBaseName() {
  return lastPathName(stripJsonSuffix(results_filename));
}