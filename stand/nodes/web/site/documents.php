<?php require __DIR__ . '/db.php'; ?>
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Документы — Счётная палата РФ (учебный стенд)</title>
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
<h2>Документы</h2>
<ul>
<?php
$res = pg_query(gis_db(), 'SELECT title, filename, uploaded_at FROM documents ORDER BY uploaded_at DESC');
while ($row = pg_fetch_assoc($res)) {
    echo '<li>' . htmlspecialchars($row['uploaded_at']) . ' — '
        . htmlspecialchars($row['title']) . ' (' . htmlspecialchars($row['filename']) . ')</li>';
}
?>
</ul>
</body>
</html>
