const filters = document.querySelectorAll('[data-filter]');
filters.forEach(button => button.addEventListener('click', () => {
  filters.forEach(item => {
    const selected = item === button;
    item.classList.toggle('selected', selected);
    item.setAttribute('aria-pressed', String(selected));
  });
  document.querySelectorAll('[data-kind]').forEach(item => {
    item.hidden = button.dataset.filter !== 'all' && item.dataset.kind !== button.dataset.filter;
  });
}));
