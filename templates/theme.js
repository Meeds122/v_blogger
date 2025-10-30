// Auto-detect system theme and apply on load
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
const savedTheme = localStorage.getItem('theme');
const body = document.body;
const themeToggle = document.querySelector('.theme-toggle');
const sunIcon = document.querySelector('.sun-icon');
const moonIcon = document.querySelector('.moon-icon');

// Apply theme: system preference first, then saved user choice
if (savedTheme) {
    body.setAttribute('data-theme', savedTheme);
} else {
    body.setAttribute('data-theme', prefersDark ? 'dark' : 'light');
}

// Sync icons based on current theme
const currentTheme = body.getAttribute('data-theme');
sunIcon.style.display = currentTheme === 'dark' ? 'none' : 'block';
moonIcon.style.display = currentTheme === 'dark' ? 'block' : 'none';

// Listen for system theme changes (live update)
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
const newSystemTheme = e.matches ? 'dark' : 'light';
// Only update if user hasn't manually set a preference
if (!localStorage.getItem('theme')) {
    body.setAttribute('data-theme', newSystemTheme);
    sunIcon.style.display = newSystemTheme === 'dark' ? 'none' : 'block';
    moonIcon.style.display = newSystemTheme === 'dark' ? 'block' : 'none';
}
});

// Toggle button handler
themeToggle.addEventListener('click', () => {
    const isDark = body.getAttribute('data-theme') === 'dark';
    const newTheme = isDark ? 'light' : 'dark';
    body.setAttribute('data-theme', newTheme);
    sunIcon.style.display = isDark ? 'block' : 'none';
    moonIcon.style.display = isDark ? 'none' : 'block';
    localStorage.setItem('theme', newTheme); // Save user preference
});