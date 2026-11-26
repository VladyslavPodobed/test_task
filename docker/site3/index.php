<?php
$hostname = gethostname();
$time = date('Y-m-d H:i:s T');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Server Info</title>
</head>
<body>
    <h1>Server Info</h1>
    <p><strong>Server time:</strong> <?php echo htmlspecialchars($time); ?></p>
    <p><strong>Hostname:</strong> <?php echo htmlspecialchars($hostname); ?></p>
</body>
</html>
