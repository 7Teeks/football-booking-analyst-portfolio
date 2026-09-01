-- =========================================================
-- Сервис бронирования футбольных полей — схема БД на postgres
-- =========================================================
CREATE TABLE complexes (
    complex_id   SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    city         VARCHAR(50)  NOT NULL
);

CREATE TABLE fields (
    field_id     SERIAL PRIMARY KEY,
    complex_id   INT NOT NULL REFERENCES complexes(complex_id),
    field_type   VARCHAR(10) NOT NULL CHECK (field_type IN ('5x5','8x8','11x11')),
    coating      VARCHAR(20) NOT NULL
);

CREATE TABLE slots (
    slot_id      SERIAL PRIMARY KEY,
    field_id     INT NOT NULL REFERENCES fields(field_id),
    slot_date    DATE NOT NULL,
    slot_time    TIME NOT NULL,
    price        NUMERIC(10,2) NOT NULL
);

CREATE TABLE users (
    user_id      SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    phone        VARCHAR(20),
    email        VARCHAR(100)
);

CREATE TABLE bookings (
    booking_id   SERIAL PRIMARY KEY,
    slot_id      INT NOT NULL REFERENCES slots(slot_id),
    user_id      INT NOT NULL REFERENCES users(user_id),
    status       VARCHAR(20) NOT NULL
                 CHECK (status IN ('Создана','Подтверждена','Отменена','Истекла','Завершена')),
    created_at   TIMESTAMP NOT NULL DEFAULT now(),
    expires_at   TIMESTAMP
);

CREATE TABLE payments (
    payment_id   SERIAL PRIMARY KEY,
    booking_id   INT NOT NULL REFERENCES bookings(booking_id),
    amount       NUMERIC(10,2) NOT NULL,
    status       VARCHAR(20) NOT NULL
                 CHECK (status IN ('Создана','Обрабатывается','Ошибка','Успешно','Возвращён')),
    created_at   TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------- ТЕСТОВЫЕ ДАННЫЕ ----------

INSERT INTO complexes (name, city) VALUES
('Спортивный комплекс "Олимп"', 'Сочи'),
('Комплекс "Арена Юг"', 'Сочи');

INSERT INTO fields (complex_id, field_type, coating) VALUES
(1, '5x5', 'искусственное'),
(1, '8x8', 'искусственное'),
(2, '11x11', 'натуральное');

INSERT INTO slots (field_id, slot_date, slot_time, price) VALUES
(1, '2026-09-05', '18:00', 2500),
(1, '2026-09-05', '20:00', 3000),
(2, '2026-09-06', '19:00', 4000),
(3, '2026-09-06', '10:00', 5000),
(3, '2026-09-07', '20:00', 7500);

INSERT INTO users (name, phone, email) VALUES
('Максим Наимушин', '+7900000001', 'maxim@example.com'),
('Иван Петров', '+7900000002', 'ivan@example.com'),
('Команда "Сокол"', '+7900000003', 'sokol@example.com');

INSERT INTO bookings (slot_id, user_id, status, created_at, expires_at) VALUES
(1, 1, 'Завершена',   now() - interval '10 days', NULL),
(2, 1, 'Подтверждена', now() - interval '2 days',  NULL),
(3, 2, 'Отменена',     now() - interval '5 days',  NULL),
(4, 2, 'Завершена',    now() - interval '15 days', NULL),
(5, 1, 'Подтверждена', now() - interval '1 days',  NULL);

INSERT INTO payments (booking_id, amount, status) VALUES
(1, 2500, 'Успешно'),
(2, 3000, 'Успешно'),
(3, 4000, 'Возвращён'),
(4, 5000, 'Успешно'),
(5, 7500, 'Успешно');

-- =========================================================
-- АНАЛИТИЧЕСКИЕ ЗАПРОСЫ (см. задачу BOOK-601 в backlog)
-- =========================================================

-- 1. Загрузка полей по дням недели
-- Показывает, в какие дни недели поля бронируют чаще всего
SELECT
    to_char(s.slot_date, 'Day')          AS day_of_week,
    COUNT(b.booking_id)                  AS bookings_count
FROM bookings b
JOIN slots s ON s.slot_id = b.slot_id
WHERE b.status IN ('Подтверждена', 'Завершена')
GROUP BY to_char(s.slot_date, 'Day'), EXTRACT(ISODOW FROM s.slot_date)
ORDER BY EXTRACT(ISODOW FROM s.slot_date);


-- 2. Выручка по типу поля за период
-- Помогает понять, какой тип поля приносит больше денег
SELECT
    f.field_type,
    SUM(p.amount)                        AS total_revenue,
    COUNT(p.payment_id)                  AS payments_count
FROM payments p
JOIN bookings b ON b.booking_id = p.booking_id
JOIN slots s    ON s.slot_id = b.slot_id
JOIN fields f   ON f.field_id = s.field_id
WHERE p.status = 'Успешно'
  AND s.slot_date BETWEEN '2026-08-01' AND '2026-09-30'
GROUP BY f.field_type
ORDER BY total_revenue DESC;


-- 3. Топ-5 клиентов по количеству броней
SELECT
    u.name,
    COUNT(b.booking_id)                  AS total_bookings
FROM bookings b
JOIN users u ON u.user_id = b.user_id
WHERE b.status IN ('Подтверждена', 'Завершена')
GROUP BY u.name
ORDER BY total_bookings DESC
LIMIT 5;


-- 4. Доступные слоты на конкретную дату (аналог REST-эндпоинта GET /fields/available-slots)
SELECT
    s.slot_id,
    f.field_type,
    s.slot_time,
    s.price
FROM slots s
JOIN fields f ON f.field_id = s.field_id
WHERE s.slot_date = '2026-09-05'
  AND NOT EXISTS (
        SELECT 1 FROM bookings b
        WHERE b.slot_id = s.slot_id
          AND b.status IN ('Создана', 'Подтверждена')
      )
ORDER BY s.slot_time;


-- 5. Суммарная сумма возвратов за месяц (для владельца сети — контроль отмен)
SELECT
    SUM(p.amount) AS total_refunded
FROM payments p
WHERE p.status = 'Возвращён'
  AND p.created_at >= date_trunc('month', now());
