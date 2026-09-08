(function () {
    var toggle = document.getElementById('theme-toggle');
    var label  = document.getElementById('theme-label');

    function applyTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        label.textContent = theme === 'dark' ? 'LIGHT' : 'DARK';
    }

    applyTheme(localStorage.getItem('theme') || 'dark');

    toggle.addEventListener('click', function () {
        var current = document.documentElement.getAttribute('data-theme');
        var next = current === 'dark' ? 'light' : 'dark';
        localStorage.setItem('theme', next);
        applyTheme(next);
    });
})();

async function fetchVisitorCount() {
    try {
        const response = await fetch(
            "https://rgmtlia3mi.execute-api.us-east-1.amazonaws.com/count",
        );
        const data = await response.json();
        document.getElementById("visit-count").textContent =
            data.count.toLocaleString();
    } catch (err) {
        document.getElementById("visit-count").textContent = "—";
    }
}

fetchVisitorCount();
