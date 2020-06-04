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
