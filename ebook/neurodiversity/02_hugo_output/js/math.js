document.getElementById("katex-auto-render")
  .addEventListener("load", renderMathInElement(document.body));

document.addEventListener("DOMContentLoaded", function () {
  renderMathInElement(document.body, {
    delimiters: [
      { left: "$$", right: "$$", display: true },
      { left: "$", right: "$", display: false }
    ]
  });
});
