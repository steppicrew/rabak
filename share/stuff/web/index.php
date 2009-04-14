<?
    // Simple CMS without name 0.1
    // (c) Copyright by Dietrich Raisin

    // License: See LICENSE file

    global $aPages, $aMenu, $sRelPath, $sIncludePath;

    $sIncludePath= "";

    // This is a ugly Hack to fetch content files from GitHub directly.
    // Further changes are some additional "?raw=true" to URLs in this file and the CSS.
    // Good enough for now, but MUST be changed if the web site has traffic...
    if ($_SERVER["HTTP_HOST"] == "www.raisin.de") {
        $sIncludePath= "http://github.com/steppicrew/rabak/tree/master/share/stuff/web/";
    }
 
    $sPageName= @$_SERVER["PATH_INFO"];
    $sRelPath= "../";

    if ($sPageName == '') {
        $sRelPath= "";

        # header("Location: http://".$_SERVER["HTTP_HOST"].$_SERVER["SCRIPT_NAME"]."/");
        # exit;
    }

    $sPageName= substr($sPageName, 1);

    getContents();

    if (!isset($aPages[$sPageName])) $sPageName= "index";

    printHtmlPage($sPageName);

    # phpinfo();

    class PAGE_PARSER {

        var $aPage;
        var $aPageTitle;
        var $aPagePrefs= array();
        var $bInsideParagraph;
        var $bInsideList;
        var $bInsideForm;
        var $bInsideCode;
        var $bFoundEmptyLine;
        var $sFormSendPageName= '';
        var $sFormSelectField= '';
        var $sFormSubmitField= '';
        var $aForm= array();
        # var $bFormSubmitted;
        var $sPage;
        var $iLine;
        var $sFormSendEmail= '';
        var $bFormHasErrors= false;

        function PAGE_PARSER($sPageName) {
            global $aPages, $aPagesTitle;
            $this->sPageName= $sPageName;
            $this->aPage= @$aPages[$sPageName];
            if (!$this->aPage) $this->aPage= array();
            $this->sPageTitle= @$aPagesTitle[$sPageName];
            # var_dump($this->sPageName); exit;
        }

        function _endAll() {
            $this->_endList();
            $this->_endParagraph();
            $this->_endCode();
        }

        function _addText($sText) {
            $sText= htmlspecialchars($sText);
 
            // Mini Textile
            $sText= preg_replace("/\*([^\*]+)\*/", "<b>$1</b>", $sText );
            $sText= preg_replace("/\@([^\@\s]+)\@/", "<code>$1</code>", $sText );

            $sMaskDomain=           "[a-zA-Z][-a-zA-Z_0-9]{2,}";
            $sMaskDomainWithDot=    "[a-zA-Z][-a-zA-Z_\.0-9]+[-a-zA-Z_0-9]";    // Min 3 Buchstaben
            $sMask1stLevelDomain=   "(org|com|net|de)";
            $sMaskFile=             $sMaskDomainWithDot;
            $sMaskPathedFile=       "($sMaskFile(\/$sMaskFile)*)";
            $sMaskPathedFile2=      "($sMaskFile(\/$sMaskFile)+)";

            $sMaskEmail= "($sMaskDomainWithDot\@$sMaskDomainWithDot\.$sMask1stLevelDomain)";
            $sMaskUrl= "((http:\/\/)?($sMaskDomain\.$sMaskDomainWithDot\.$sMask1stLevelDomain(\/$sMaskPathedFile)?\/?))";
            $sMaskIdentifier= "([a-z][a-z0-9_]*)";

            $sMaskParam= "\s+([^\}]+?)\s*\}";

            // Normale Web-Adressen verlinken
            $sText= preg_replace("/$sMaskUrl/", "{link http://$3 $1}", $sText);

            // Falls das Parameter für {link .. } waren: korrigieren
            $sText= preg_replace("/\{link\s+\{link\s+$sMaskUrl$sMaskParam$sMaskParam/",
                "{link $3 $9}", $sText
            );

            // {link URL .. } ersetzen
            $sText= preg_replace("/\{link\s+$sMaskUrl$sMaskParam/",
                "<a target=_blank href=\"http://$3\">$8</a>", $sText
            );

            global $sRelPath;

            // {link File .. } ersetzen
            $sText= preg_replace("/\{link\s+$sMaskPathedFile2$sMaskParam/",
                "<a target=_blank href=\"$sRelPath$1\">$3</a>", $sText
            );

            // {link page .. } ersetzen
            global $aPages;
            $sText= preg_replace("/\{link\s+$sMaskIdentifier$sMaskParam/e",
                "isset(\$aPages['$1']) ? '<a href=\"'.getUrl('$1').'\">$2</a>' : '$2'", $sText
            );

            // {bold page .. } ersetzen
            $sText= preg_replace("/\{bold$sMaskParam/", "<b>$1</b>", $sText );

            // E-Mail-Adressen verlinken
            $sText= preg_replace("/$sMaskEmail/", "<a href=\"mailto:$1\">$1</a>", $sText);

            $this->sPage .= $sText;
        }

        function _insideCode() {
            $this->_endAll();
            $this->bInsideCode= true;
            $this->sPage .= "\n<div class='code'><code>";
        }

        function _endCode() {
            if (!$this->bInsideCode) return;
            $this->bInsideCode= false;
            $this->sPage .= "\n</code></div>";
        }

        function _insideParagraph() {
            $bOldState= $this->bInsideParagraph;
            if (!$this->bInsideParagraph) {
                $this->_endAll();
                $this->bInsideParagraph= true;
                $this->sPage .= "\n<p>";
            }
            return $bOldState;
        }

        function _endParagraph() {
            if (!$this->bInsideParagraph) return;
            $this->bInsideParagraph= false;
            $this->sPage .= "\n</p>";
        }

        function _insideList() {
            $this->_endAll();
            $this->bInsideList= true;
            $this->sPage .= "\n<p class=\"list\">";
        }

        function _endList() {
            if (!$this->bInsideList) return;
            $this->bInsideList= false;
            $this->sPage .= "\n</p>";
        }

        function _addFormField($sType, $sCaption= '') {
            $sFieldName= "f".count($this->aForm);
            $oField= & new StdClass;
            $oField->sType= $sType;
            $oField->sCaption= $sCaption;
            $oField->sValue= substr(@$_POST[$sFieldName], 0, $sType == '_textarea' ? 8000 : 200);
            $oField->aOptions= array();
            $this->aForm[$sFieldName]= & $oField;
            return $sFieldName;
        }

        function _addFormFieldText($sFieldName, $sText) {
            $sCaption= $this->aForm[$sFieldName]->sCaption;
            $sError= '';
            if ($this->_wasFormSubmitted()) {
                # print $sCaption.'*'.$this->aForm[$sFieldName]->sValue.'*<br>';
                if (preg_match("/\*$/", $sCaption) && $this->aForm[$sFieldName]->sValue == '') {
                    $sError= "<p class=\"formerror\">Bitte dieses Feld ausfüllen!</p>";
                    $this->bFormHasErrors= true;
                }
            }
            $this->sPage .= "\n<table><tr valign=top><td>";
            if ($sCaption != '') {
                $this->_addText("$sCaption:");
            }
            $this->sPage .= "</td><td>$sError$sText</td></table>";
        }

        function _wasFormSubmitted() {
            return $this->sFormSubmitField && $this->aForm[$this->sFormSubmitField]->sValue;
        }

        function getFormSendPageName() {
            if (!$this->bFormHasErrors && $this->_wasFormSubmitted()) return $this->sFormSendPageName;
            return '';
        }

        function getFormSendEmail() {
            return $this->sFormSendEmail;
        }

        function getFormAsText() {
            $sResult= '';
            foreach ($this->aForm as $sFieldName => $oField) {
                switch ($oField->sType) {
                    case '_text':
                    case '_textarea':
                    case '_email':
                    case '_select':
                            $sResult .= $oField->sCaption.': '.$oField->sValue."\n";
                            break;
                }
            }
            return $sResult;
        }

        function getPagePrefs() {
            return $this->aPagePrefs;
        }

        function getPageTitle() {
            return $this->sPageTitle;
        }

        function _error($sMsg) {
            global $aPagesFirstLine;
            $iLine= $aPagesFirstLine[$this->sPageName] + min($this->iLine, count($this->aPage)-1);
            gcError($iLine, @$this->aPage[$this->iLine], $sMsg);
        }

        function parse() {
    
            $aPage= $this->aPage;

            $this->sPage= '';
            $this->bInsideParagraph= false;
            $this->bInsideList= false;
            $this->bInsideForm= false;
            $this->bInsideCode= false;
            $this->bFoundEmptyLine= false;
            $this->bFormSubmitted= false;
            $this->sFormSendEmail= '';
            $this->bFormHasErrors= false;
   
            for($this->iLine= 0; $this->iLine < count($aPage); $this->iLine++) {
                $sLine= $aPage[$this->iLine];

                if (preg_match("/^;/", $sLine)) continue;
    
                if (!$sLine) {
                    $this->bFoundEmptyLine= true;
                    $this->_endAll();
                    continue;
                }
    
                if (preg_match("/^##(\S+)(\s+(.+))?/", $sLine, $aMatch)) {
                    $sCmd= $aMatch[1];
                    $sParam= @$aMatch[3];

                    if ($sCmd == "end" && $this->bInsideCode) {
                        $this->_endAll();
                        continue;
                    }
    
                    if ($sCmd == "code") {
                        $this->_endAll();
                        $this->_insideCode();
                        continue;
                    }
    
                    if ($sCmd == "title" || $sCmd == "keywords" || $sCmd == "description" || $sCmd == "headimage_text") {
                        $this->aPagePrefs[$sCmd]= $sParam;
                        continue;
                    }

                    if ($sCmd == "h1" || $sCmd == "h2") {
                        $this->_endAll();
                        $this->sPage .= "\n<$sCmd>";
                        $this->_addText($sParam);
                        $this->sPage .= "\n</$sCmd>";
                        $this->bFoundEmptyLine= false;
                        continue;
                    }
    
                    if ($sCmd == "image" || $sCmd == "leftimage" || $sCmd == "rightimage") {
                        if ($this->bFoundEmptyLine) {
                            $this->sPage .= "<br clear=all>";
                        }
                        $this->_endAll();
                        if (!preg_match("/^(\S+)(\s+(.*))?/", $sParam, $aMatch)) {
                            $this->_error("Syntax Fehler in ##image-Anweisung");
                        }
                        $sFile= $aMatch[1];
                        $sCaption= @$aMatch[3];

                        $aSize= @getimagesize("images/$sFile");
                        if ($aSize == false) {
                            $this->_error("Bild-Datei \"$sFile\" existiert nicht!");
                        }

                        $sAlign= "center";
                        if ($sCmd == "leftimage") $sAlign= "left";
                        if ($sCmd == "rightimage") $sAlign= "right";
                        $this->sPage .= "\n<table border=0 cellspacing=0 cellpadding=0 align=\"$sAlign\"><tr><td>";
                        if ($sAlign == "right") $this->sPage .= "&nbsp;&nbsp;&nbsp;</td><td>";
                        $this->sPage .= "<img src=\"".getImageUrl($sFile)."\" ".$aSize[3].">";
                        if ($sCaption) {
                            $this->sPage .= "</td></tr><tr><td>";
                            if ($sAlign == "right") $this->sPage .= "</td><td>";
                            $this->sPage .= "<div class=\"imgtext\">";
                            $this->_addText($sCaption);
                            $this->sPage .= "</div>&nbsp;";
                        }
                        else {
                            $this->sPage .= "<br>&nbsp;";
                        }
                        if ($sAlign == "left") $this->sPage .= "</td><td>&nbsp;&nbsp;&nbsp;";
                        $this->sPage .= "</td></tr></table>";
                        $this->bFoundEmptyLine= false;
                        continue;
                    }

                    if (substr($sCmd, 0, 4) == "form") {
                        $sCmd= substr($sCmd, 4);
                        if ($sCmd == "_send") {
                            if ($this->bInsideForm) {
                                $this->_error("form_send darf nicht innerhalb eines Formular vorkommen");
                            }
                            $this->sFormSendEmail= $sParam;
                            continue;
                        }
                        if ($sCmd == "") {
                            if ($this->bInsideForm) {
                                $this->_error("Ein Formular wurde nicht mit ''##form_submit'' abgeschlossen");
                            }
                            if ($this->aForm) {
                                $this->_error("Mehrere Formulare pro Seite werden nicht unterstützt! (Dietrich fragen)");
                            }
                            global $aPages;
                            if (!isset($aPages[$sParam])) {
                                $this->_error("Seite zum Senden existiert nicht!");
                            }
                            $this->sFormSendPageName= $sParam;
                            $this->bInsideForm= true;
                            $this->sPage .= "\n<form action=\"".getUrl($this->sPageName)."\" method=post>";
                            $sFieldName= $this->_addFormField('_submit_page');
                            $this->sPage .= "\n<input type=hidden name=\"$sFieldName\" value=\"1\">";
                            $this->sFormSubmitField= $sFieldName;
                            continue;
                        }
                        if (!$this->bInsideForm) {
                            $this->_error("Ein Formular wurde nicht mit ''##form'' begonnen");
                        }
                        if ($sCmd == "_option") {
                            if (!$this->sFormSelectField) {
                                $this->_error("''##form_option'' erfordert vorheriges ''##form_select''");
                            }
                            $this->aForm[$this->sFormSelectField]->aOptions[]= $sParam;
                            continue;
                        }
                        if ($this->sFormSelectField) {
                            $sText= "\n<option value=\"\">Bitte w&auml;hlen!</option>";
                            foreach ($this->aForm[$this->sFormSelectField]->aOptions as $sOption) {
                                $sOptionValue= htmlspecialchars($sOption);
                                $sText .= "\n<option";
                                if ($this->aForm[$this->sFormSelectField]->sValue == $sOptionValue) {
                                    $sText .= " selected";
                                }
                                $sText .= ">$sOptionValue</option>";
                            }
                            $sText= "<select name=\"".$this->sFormSelectField."\">$sText</select>";
                            $this->_addFormFieldText($this->sFormSelectField, $sText);
                            $this->sFormSelectField= '';
                        }
                        if ($sCmd == "_text" || $sCmd == "_email") {
                            $sFieldName= $this->_addFormField($sCmd, $sParam);
                            $sText= htmlspecialchars(@$_POST[$sFieldName]);
                            $sText= "<input type=text name=\"$sFieldName\" value=\"$sText\">";
                            $this->_addFormFieldText($sFieldName, $sText);
                            continue;
                        }
                        if ($sCmd == "_textarea") {
                            $sFieldName= $this->_addFormField($sCmd, $sParam);
                            $sText= htmlspecialchars(@$_POST[$sFieldName]);
                            $sText= "<textarea wrap=on name=\"$sFieldName\">$sText\n</textarea>";
                            $this->_addFormFieldText($sFieldName, $sText);
                            continue;
                        }
                        if ($sCmd == "_select") {
                            $this->sFormSelectField= $this->_addFormField($sCmd, $sParam);
                            continue;
                        }
                        if ($sCmd == "_submit") {
                            $sFieldName= $this->_addFormField($sCmd);
                            $sText= "<input type=submit name=\"$sFieldName\" value=\"$sParam\">";
                            $this->_addFormFieldText($sFieldName, $sText);
                            $this->sPage .= "\n</form>";
                            $this->bInsideForm= false;
                            continue;
                        }
                        $this->_error("Unbekannte FORM-Anweisung ''##form_$sCmd''.
                            Erlaubt sind: ##form, ##form_text, ##form_select + ##form_option, 
                            ##form_textarea, ##form_email und ##form_submit
                        ");
                    }

                    $this->_error("Unbekannte Anweisung ''##$sCmd''");
                }

                if (preg_match("/^[-]\s/", $sLine)) {
                    if ($this->bFoundEmptyLine) {
                        $this->sPage .= "<br>";
                    }
                    $this->_insideList();
                    $this->_addText($sLine);
                    $this->bFoundEmptyLine= false;
                    continue;
                }

                if ($this->bInsideList && preg_match("/^\s/", $sLine)) {
                    $this->_addText(" $sLine");
                    $this->bFoundEmptyLine= false;
                    continue;
                }

                if ($this->bInsideCode) {
                    $this->_addText($sLine);
                    $this->sPage .= "<br />";
                    continue;
                }

                if ($this->_insideParagraph()) {
                    if (substr($this->sPage, -1, 1) == ':') {
                        $this->sPage .= "<br />";
                    }
                    else {
                        $this->_addText(' ');
                    }
                }
                $this->_addText($sLine);
                $this->bFoundEmptyLine= false;
                continue;
            }

            if ($this->bInsideForm) {
                $this->_error("Ein Formular wurde nicht mit ''form_submit'' abgeschlossen");
            }

            $this->sPage .= "<br><br><br>";

            return $this->sPage;
        }
    }

    function getUrl($sPageName) {
        if ($sPageName == "index") return substr($_SERVER["SCRIPT_NAME"], 0, strrpos($_SERVER["SCRIPT_NAME"], '/') + 1);
        return $_SERVER["SCRIPT_NAME"] . "/$sPageName";
    }

    function getImageUrl($sImageFile) {
        global $sRelPath;

        return $sRelPath."images/".$sImageFile;
    }

    function getLink($sPageName, $sText) {
        return "<a href=\"".getUrl($sPageName)."\">$sText</a>";
    }

    function _parseMenu($sPageName, $aMenu) {
        global $aPages;

        # $aMenu[]= ''; // close para
        $iState= 0;
        $sMenu= "";
        $sLastMenuPage= "";
        $sActiveMenuPage= "";
        for ($iPass= 0; $iPass < 2; $iPass++) {
            for($iLine= 0; $iLine < count($aMenu); $iLine++) {
                $sLine= $aMenu[$iLine];

                if (preg_match("/^;/", $sLine)) continue;
    
                if (!preg_match("/^(\s*)([a-z][a-z_0-9]*):\s*(.*)$/", $sLine, $aMatch)) {
                    gcError($iLine, $sLine, "Fehler in Menudefinition");
                }
                $sMenuPage= $aMatch[2];
                if (!isset($aPages[$sMenuPage])) continue;

                $sMenuText= $aMatch[3];

                if (strlen($aMatch[1]) > 0) {
                    if ($iPass && $sLastMenuPage == $sActiveMenuPage) {
                        $sClass= ($sMenuPage == $sPageName) ? " active" : "";
                        $sMenu .= "\n<p class=\"menulevel1$sClass\">".getLink($sMenuPage, $sMenuText)."</p>";
                    }
                    # if (!$iPass && $sMenuPage == $sPageName) $sActiveMenuPage= $sLastMenuPage;
                }
                else {
                    if ($iPass) {
                        $sClass= ($sMenuPage == $sPageName) ? " active" : "";
                        $sMenu .= "\n<p class=\"menulevel0$sClass\">".getLink($sMenuPage, $sMenuText)."</p>";
                    }
                    $sLastMenuPage= $sMenuPage;
                }

                if (!$iPass && $sMenuPage == $sPageName) $sActiveMenuPage= $sLastMenuPage;

                # if (!$iPass) print "::".$sMenuPage."::".$sMenuText."::$sActiveMenuPage::$sPageName<br>";
            }
        }
        return $sMenu;
    }

    function printHtmlPage($sPageName) {
        global $aPages, $aMenu, $sRelPath, $sIncludePath;

        $oPage= & new PAGE_PARSER('global');
        $oPage->parse();

        $aGlobalPrefs= $oPage->getPagePrefs();

        $oPage= & new PAGE_PARSER($sPageName);
        $sPage= $oPage->parse();

        $sFormSendPageName= $oPage->getFormSendPageName();
        if ($sFormSendPageName) {
            $oSendPage= & new PAGE_PARSER($sFormSendPageName);
            $sPage= $oSendPage->parse();

            $sFormSendEmail= $oSendPage->getFormSendEmail();
            if (!$sFormSendEmail) {
                gcError(0, "", "Seite ''$sFormSendPageName'' enthaelt keine ''##form_send''-Anweisung!");
            }

            if (!mail($sFormSendEmail, "Buchungsanfrage", $oPage->getFormAsText())) {
                print "Ihre Mail konnte leider nicht versandt werden!
                    Bitte infomieren Sie webmaster@".$_SERVER["HTTP_HOST"]."! DANKE!!";
            }
        }

        $sMenu= 'menu1';
        $aMenu= @$aMenu[$sMenu];
        if (!isset($aMenu)) $aMenu= array();

        $sMenu= _parseMenu($sPageName, $aMenu);

        $aPagePrefs= $oPage->getPagePrefs();

        $sPageKeywords= @$aPagePrefs['keywords'] ? $aPagePrefs['keywords'] : @$aGlobalPrefs['keywords'];
        $sPageDescription= @$aPagePrefs['description'] ? $aPagePrefs['description'] : @$aGlobalPrefs['description'];
        $sPageHeadImageText= @$aPagePrefs['headimage_text'] ? $aPagePrefs['headimage_text'] : @$aGlobalPrefs['headimage_text'];

        if (@$aPagePrefs['title']) {
            $sPageTitle= $aPagePrefs['title'];
        }
        else {
            $sPageTitle= $oPage->getPageTitle();
            if (@$aGlobalPrefs['title'] && $sPageTitle) $sPageTitle= $aGlobalPrefs['title'].": ".$sPageTitle;
        }

        $aSize= @getimagesize("images/head.gif");
        $sImg= '<img border=0 src="'.getImageUrl('head.gif').'" '.@$aSize[3].' alt="'.$sPageHeadImageText.'">';
        $sHead= getLink('index', $sImg);
?>
<html>
    <head>
        <title><?= $sPageTitle ?></title>
        <meta name="keywords" content="<?= $sPageKeywords ?>">
        <meta name="description" content="<?= $sPageDescription ?>">
        <link rel="stylesheet" type="text/css" href="<?= $sIncludePath ?>screen.css?raw=true">
    </head>
    <body class="default">
        <div id="container">
                <div id="head"><h1><?= $sPageTitle ?></h1><?= $sHead ?></div>
                <div id="menu"><?= $sMenu ?></div>
                <div id="content"><?= $sPage ?></div>
                <br clear="all" />
                <div id="footer"></div>
        </div>
    </body>
</html>
<?
    }


    function gcError($iLine, $sLine, $sMsg) {
        print "<h1>Fehler in der Datei content.txt</h1>";
        print "<h2>";
        if ($iLine) print "Zeile ".($iLine+1);
        if ($sLine) print ": $sLine";
        print "</h2>";
        print "<h2>$sMsg!</h2>";
        exit;
    }

    function getContents() {
        global $sIncludePath;
        $sContents= file_get_contents($sIncludePath . "content.txt?raw=true");

        global $aPages, $aPagesFirstLine, $aPagesTitle, $aMenu;
        $aPages= array();
        $aPagesFirstLine= array();
        $aPagesTitle= array();
        $aMenu= array();

        $iState= 0;
        $sPageName= "";

        $aLines= preg_split("/\n\r?/", $sContents);

        for($iLine= 0; $iLine < count($aLines); $iLine++) {

            $sLine= $aLines[$iLine];
            switch ($iState) {

                case 0:
                        // Fetch page
                        if (preg_match("/^;/", $sLine)) continue;
                        
                        if (preg_match("/^==(.*)/", $sLine, $aMatch)) {
                            $sPageName= trim($aMatch[1]);
                            if (!preg_match("/^([a-z][a-z0-9_]*)(:\s*(.*))?$/", $sPageName, $aMatch)) {
                                gcError($iLine, $sLine, "Ungueltiger Seitenname");
                                return;
                            }
                            $sPageName= $aMatch[1];
                            $sPageTitle= @$aMatch[3];
                            if (isset($aPages[$sPageName])) {
                                gcError($iLine, $sLine, "Seite ''$sPageName'' ist doppelt");
                                return;
                            }
                            if (preg_match("/^menu/", $sPageName)) {
                                if (isset($aMenu[$sPageName])) {
                                    gcError($iLine, $sLine, "Menue ''$sPageName'' ist doppelt");
                                    return;
                                }
                                $aMenu[$sPageName]= array();
                                $iState= 2;
                                break;
                            }
                            $aPages[$sPageName]= array();
                            $aPagesFirstLine[$sPageName]= $iLine+1;
                            $aPagesTitle[$sPageName]= $sPageTitle;
                            $iState= 1;
                            break;
                        }
                        if (trim($sLine) == '') break;
                        gcError($iLine, $sLine, "==Seite erwartet");
                        break;

                case 1:
                        if (preg_match("/^==(.*)/", $sLine, $aMatch)) {
                            $iLine--;
                            $iState= 0;
                            break;
                        }

                        // Fetch page contents
                        $aPages[$sPageName][]= rtrim($sLine);
                        break;

                case 2:
                        if (preg_match("/^==(.*)/", $sLine, $aMatch)) {
                            $iLine--;
                            $iState= 0;
                            break;
                        }

                        // Fetch menu
                        if (trim($sLine)) {
                            $aMenu[$sPageName][]= rtrim($sLine);
                        }
                        break;
            }
        }
    }

?>
