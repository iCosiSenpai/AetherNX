// The shelves: pulling a spine (pointer, focus, or the arrow keys along a shelf) slides it out and puts its game in the case beside the shelf.
const REPO = 'https://github.com/iCosiSenpai/AetherNX/blob/main/dm/games/';

function setup(shelf) {
  const box = document.getElementById(shelf.dataset.case);
  if (!box) return;
  const shot = box.querySelector('.case-shot');
  const name = box.querySelector('.case-name');
  const note = box.querySelector('.case-note');
  const link = box.querySelector('.case-link');
  const spines = () => [...shelf.querySelectorAll('.spine')].filter(s => s.offsetParent !== null);
  let current = shelf.querySelector('.spine.is-out');
  let timer = 0;

  function pull(spine, focus) {
    if (!spine || spine === current) { if (focus && spine) spine.querySelector('button').focus(); return; }
    if (current) { current.classList.remove('is-out'); current.querySelector('button').tabIndex = -1; }
    current = spine;
    spine.classList.add('is-out');
    const button = spine.querySelector('button');
    button.tabIndex = 0;
    if (focus) button.focus();
    clearTimeout(timer);
    box.classList.add('is-swapping');
    const next = new Image();
    next.src = spine.dataset.shot;
    const show = () => {
      shot.src = spine.dataset.shot;
      shot.alt = `${spine.dataset.name}, captured running in HorizonNative`;
      name.textContent = spine.dataset.name;
      note.textContent = spine.dataset.note;
      if (link && spine.dataset.tid) link.href = `${REPO}${spine.dataset.tid}/README.md`;
      timer = setTimeout(() => box.classList.remove('is-swapping'), 30);
    };
    next.decode ? next.decode().then(show, show) : (next.onload = show);
  }

  // one tab stop per shelf; the arrows walk it
  shelf.querySelectorAll('.spine button').forEach(b => { b.tabIndex = -1; });
  (current || shelf.querySelector('.spine'))?.querySelector('button').setAttribute('tabindex', '0');

  shelf.addEventListener('pointerover', e => { const s = e.target.closest('.spine'); if (s && e.pointerType === 'mouse') pull(s, false); });
  shelf.addEventListener('click', e => { const s = e.target.closest('.spine'); if (s) pull(s, false); });
  shelf.addEventListener('focusin', e => { const s = e.target.closest('.spine'); if (s) pull(s, false); });
  shelf.addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(e.key)) return;
    const list = spines(); const i = list.indexOf(current);
    const step = e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 1;
    const target = e.key === 'Home' ? list[0] : e.key === 'End' ? list[list.length - 1] : list[Math.min(list.length - 1, Math.max(0, i + step))];
    if (target) { e.preventDefault(); pull(target, true); target.scrollIntoView({ block: 'nearest', inline: 'nearest' }); }
  });
  return pull;
}

document.querySelectorAll('.shelf').forEach(setup);

// the wall's filter
const wall = document.querySelector('.shelf-wall');
document.querySelectorAll('.filter button').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.filter button').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
    wall.dataset.filter = button.dataset.filter;
  });
});
