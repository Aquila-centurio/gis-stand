-- Схема БД site. Идемпотентно: можно выполнять повторно при каждом запуске контейнера.

CREATE TABLE IF NOT EXISTS news (
    id serial PRIMARY KEY,
    title text NOT NULL,
    body text NOT NULL,
    published_at date NOT NULL DEFAULT current_date
);

CREATE TABLE IF NOT EXISTS documents (
    id serial PRIMARY KEY,
    title text NOT NULL,
    filename text NOT NULL,
    uploaded_at date NOT NULL DEFAULT current_date
);

-- Таблица без грантов webapp: нужна для проверки, что webapp не видит чужие данные.
CREATE TABLE IF NOT EXISTS internal_notes (
    id serial PRIMARY KEY,
    note text NOT NULL
);

INSERT INTO news (title, body, published_at)
SELECT * FROM (VALUES
    ('Счётная палата опубликовала отчёт за 2025 год', 'Итоговый отчёт о результатах контрольных мероприятий размещён в разделе «Документы».', DATE '2026-01-15'),
    ('Обновлён состав коллегии', 'Информация об изменениях в составе коллегии Счётной палаты РФ.', DATE '2026-02-03'),
    ('Плановая проверка завершена', 'Завершена плановая проверка использования бюджетных средств в 2025 году.', DATE '2026-03-10')
) AS v(title, body, published_at)
WHERE NOT EXISTS (SELECT 1 FROM news);

INSERT INTO documents (title, filename, uploaded_at)
SELECT * FROM (VALUES
    ('Отчёт о результатах контрольного мероприятия №12', 'otchet-12.pdf', DATE '2026-01-15'),
    ('Положение о коллегии', 'polozhenie-kollegiya.pdf', DATE '2026-02-03'),
    ('Годовой отчёт 2025', 'godovoy-otchet-2025.pdf', DATE '2026-03-10')
) AS v(title, filename, uploaded_at)
WHERE NOT EXISTS (SELECT 1 FROM documents);

INSERT INTO internal_notes (note)
SELECT 'Служебная заметка: доступ только для postgres, webapp это видеть не должен.'
WHERE NOT EXISTS (SELECT 1 FROM internal_notes);

GRANT CONNECT ON DATABASE site TO webapp;
GRANT USAGE ON SCHEMA public TO webapp;
GRANT SELECT ON news, documents TO webapp;
REVOKE ALL ON internal_notes FROM webapp;
