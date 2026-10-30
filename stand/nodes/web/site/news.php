<?php require __DIR__ . '/db.php'; ?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Новости — Счётная палата РФ (учебный стенд)</title>
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
<h2>Новости</h2>
<?php
$res = pg_query(gis_db(), 'SELECT title, body, published_at FROM news ORDER BY published_at DESC');
while ($row = pg_fetch_assoc($res)) {
    echo '<article>';
    echo '<h3>' . htmlspecialchars($row['title']) . '</h3>';
    echo '<p class="date">' . htmlspecialchars($row['published_at']) . '</p>';
    echo '<p>' . htmlspecialchars($row['body']) . '</p>';
    echo '</article>';
}
?>
</body>
</html>
