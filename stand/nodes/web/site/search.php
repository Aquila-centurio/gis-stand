<?php require __DIR__ . '/db.php'; ?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Поиск — Счётная палата РФ (учебный стенд)</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<header>
<h1>Интернет-сайт Счётной палаты РФ — учебный стенд ГИС «АУО»</h1>
<nav>
<a href="index.php">Главная</a>
<a href="news.php">Новости</a>
<a href="documents.php">Документы</a>
<a href="search.php">Поиск</a>
</nav>
</header>
<h2>Поиск по новостям</h2>
<form method="get" action="search.php">
    <input type="text" name="q" value="<?php echo isset($_GET['q']) ? htmlspecialchars($_GET['q']) : ''; ?>">
    <button type="submit">Искать</button>
</form>
<?php if (isset($_GET['q']) && $_GET['q'] !== ''): ?>
<p>
Результаты по запросу:
<?php
// Учебная уязвимость: поисковая строка выводится в HTML без htmlspecialchars,
// намеренно для демонстрации XSS и срабатывания IDS/IPS на этапе 03.
echo $_GET['q'];
?>
</p>
<?php
$q = '%' . $_GET['q'] . '%';
$res = pg_query_params(gis_db(), 'SELECT title, body, published_at FROM news WHERE title ILIKE $1 ORDER BY published_at DESC', [$q]);
while ($row = pg_fetch_assoc($res)) {
    echo '<article>';
    echo '<h3>' . htmlspecialchars($row['title']) . '</h3>';
    echo '<p class="date">' . htmlspecialchars($row['published_at']) . '</p>';
    echo '<p>' . htmlspecialchars($row['body']) . '</p>';
    echo '</article>';
}
?>
<?php endif; ?>
</body>
</html>
