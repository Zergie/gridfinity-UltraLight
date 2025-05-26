const tables = document.querySelectorAll('table');
tables.forEach((table) => {
    table.addEventListener('mouseover', (e) => {
        const cell = e.target.closest('td, th');
        if (!cell) return;

        const colIndex = cell.cellIndex;
        for (let row of table.rows) {
            if (row.cells[colIndex]) {
                row.cells[colIndex].classList.add('highlight');
            }
        }
    });

    table.addEventListener('mouseout', (e) => {
        const cell = e.target.closest('td, th');
        if (!cell) return;

        const colIndex = cell.cellIndex;
        for (let row of table.rows) {
            if (row.cells[colIndex]) {
                row.cells[colIndex].classList.remove('highlight');
            }
        }
    });
});