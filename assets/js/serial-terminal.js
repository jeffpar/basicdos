/* Keep the 80x24 serial terminal (or printer) pane aligned with the responsive monitor canvas. */
(() => {
    const machine = document.getElementById("ibm5160");
    const monitor = machine?.querySelector(".pcjs-video canvas");
    const terminal = machine?.querySelector(".pcjs-serial textarea, .pcjs-parallel textarea");
    if (!monitor || !terminal) return;

    const measure = document.createElement("canvas").getContext("2d");
    if (!measure) return;

    const resize = () => {
        const height = monitor.getBoundingClientRect().height;
        if (!height) return;
        terminal.style.height = `${height}px`;

        const style = getComputedStyle(terminal);
        const verticalPadding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
        const horizontalPadding = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
        const lineHeight = (terminal.clientHeight - verticalPadding) / terminal.rows;
        measure.font = `100px ${style.fontFamily}`;
        const characterWidth = measure.measureText("M").width / 100;
        const fontSize = Math.min(lineHeight * 0.85,
            (terminal.clientWidth - horizontalPadding) / (terminal.cols * characterWidth));
        terminal.style.lineHeight = `${lineHeight}px`;
        terminal.style.fontSize = `${fontSize}px`;
    };

    const observer = new ResizeObserver(resize);
    observer.observe(monitor);
    observer.observe(terminal);
    document.fonts.ready.then(resize);
    resize();
})();
