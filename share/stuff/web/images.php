<?

    $hDir = opendir('images');
    if (!$hDir) {
        print "Fehler: images-Verzeichnis nicht gefunden!";
        exit;
    }

    while (false !== ($sDir = readdir($hDir))) {
        if ($sDir == "." || $sDir == "..") continue;

        if (is_dir("images/$sDir")) {


            $hFile = opendir("images/$sDir");
            if (!$hFile) continue;

            print "<h1>$sDir</h1>";

            while (false !== ($sFile = readdir($hFile))) {
                if ($sFile == "." || $sFile == "..") continue;

                $sFullFile= "images/$sDir/$sFile";

                if (!is_file($sFullFile)) continue;

                $aSize= getimagesize($sFullFile);

                if ($aSize == false) continue;

                # var_dump($aSize);

                print "<h2>##image $sDir/$sFile</h2>";
                print "<p>Gr&ouml;&szlig;e: ".$aSize[0]."x".$aSize[1]."<br>";
                print "<br>";
                print "<img src=\"$sFullFile\" ".$aSize[3]."><br>";
                print "<br>";
                print "</p>";

            }
            closeDir($hFile);

        }
        #echo "$sFile\n";
    }
    closedir($hDir);

?>
