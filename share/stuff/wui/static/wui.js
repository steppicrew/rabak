
jQuery(function($) {

// ============================================================================
//      Globals
// ============================================================================

    var conf= {};


// ============================================================================
//      Utility Functions
// ============================================================================

    var strcmp= function(a, b) {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    };

    var show_login_form= function() {
        var message= loginError ? "Login failed!! Please try again..." : "Welcome, please log in!";
        $('#body').html(''
                + '<h1>' + message + '</h1>'
                + '<div id="login"><form action="/login" method="post">'
                +     '<input type="hidden" name="sid" value="' + sid + '" />'

                +     '<p>Hallo Stephan, login ist steppi + s</p>'

                +     '<p>User: <input name="usr" /></p>'
                +     '<p>Password: <input name="pw" /></p>'
                +     '<p><input type="submit" /></p>'
                + '</form></div>'
            )
            .find('[name=usr]').focus();
    };

    // TODO: stop pending api calls ?
    var api= function(cmd, args, callback, errorCallback) {
        if (!args) args= {};
        args['cmd']= cmd;
        args['sid']= sid;
        
        $.ajax({
            url: "/api",
            type: "GET",
            data: args,
            dataType: "json",
            success: function(data, status) {
                if (data.error == 401) {
                    show_login_form();
                }
                if (data.error && errorCallback) {
                    errorCallback(data);
                    return;
                }
                callback(data);
            },
            error: function(xhr, status, e) {
                var result= { error: -1, error_text: 'Ajax call returned ' + status };
                errorCallback ? errorCallback(result) : callback(result);
            }
        });
    };

    var mergeData= function(data) {

        var _mergeData= function(src, dst) {
            for (var i in src) {
                if (typeof src[i] == 'object') {
                    if (typeof dst[i] != 'object') dst[i]= {};
                    _mergeData(src[i], dst[i]);
                    continue;
                }
                dst[i]= src[i];
            }
        };

        _mergeData(data.conf, conf);
    };


    var map= function(objs, fn) {
        for (var i in objs) fn(i, objs[i]);
    };

    // Same as "map", but sorts the object properties before mapping
    var sortMap= function(objs, sortFn, mapFn) {
        var lookup= [];
        for (var i in objs) lookup.push(i);
        lookup.sort(function(a,b) { return sortFn(objs[a], objs[b]); });
        for (var i in lookup) mapFn(lookup[i], objs[lookup[i]]);
    };


// ============================================================================
//      Date/Time Utils
// ============================================================================

    var timeStrToDateObj= function(timeStr, cmpTime) {
        timeStr= timeStr.replace(/^(....)(..)(..)(..)(..)(..)$/, "$2 $3, $1 $4:$5:$6 GMT");
        return new Date(timeStr);
    };

    var fmtDateObj= function(d, cmpDate) {
        var f2= function(i) { return i < 10 ? '0' + i : i; };
        var ymd= d.getFullYear() + '-' + f2(d.getMonth() + 1) + '-' + f2(d.getDate())
        var hms= f2(d.getHours()) + ':' + f2(d.getMinutes()) + ':' + f2(d.getSeconds());
        if (cmpDate) {
            var cmpYMD= d.getFullYear() + '-' + f2(d.getMonth() + 1) + '-' + f2(d.getDate());
            if (ymd == cmpYMD) return hms;
        }
        return ymd + ' ' + hms;
    };

    var fmtTime= function(timeObj) {
        var start= timeStrToDateObj(timeObj.start);
        var end= timeStrToDateObj(timeObj.end);
        return fmtDateObj(start) + ' ... ' + fmtDateObj(end, start);
    };

    
// ============================================================================
//      Html Builder Helper Class
// ============================================================================

    var Html= function(pre, post) {
        var items= [];

        this.add= function(pre, post) {
            var item= new Html(pre, post);
            items.push(item);
            return item;
        };

        this.addTable= function() {
            return this.add('<table border="1">', '</table>');
        };

        this.addRow= function(row) {
            return this.add('<tr><td>' + row.join('</td><td>') + '</td></tr>');
        };

        this.render= function() {
            var result= pre ? [ pre ] : [];
            for (var i in items) {
                result.push(items[i].render());
            }
            if (post) result.push(post);
            return result.join('');
        };
        
        return this;
    };


// ============================================================================
//      Commands
// ============================================================================

    var cmds= {};

    cmds.show_dashboard= function(params) {

        params= $.extend(params, { bakset: '*' });
        api('GetSessions', params, function(data) {
            console.log(data);
            if (data.error) return;

            mergeData(data);
            console.log(conf);

            var html= new Html();
            html.add('<h1>' + conf.title + '</h1>');

            var dashboardHtml= html.add('<div id="dashboard">', '</div>');

            map(conf.baksets, function(bakset_name, bakset) {
                var baksetHtml= dashboardHtml.add('<div style="border: 1px solidblack; float: left; width: 200px;">', '</div>');
                baksetHtml.add('<h2>' + bakset.title + '</h2>');

                sortMap(bakset.sessions,
                    function(a, b) {
                        return strcmp(b.time.start, a.time.start);
                    },
                    function(session_id, session) {
                        session.title= fmtTime(session.time);
                        baksetHtml.add('<h3>Session ' + session.title + '</h3>');

// source.stats.text ? source.stats.text.split('\n').join('<br>\n') : '',

                        var tableHtml= baksetHtml.addTable();
                        map(session.sources, function(source_name, source) {

                            // TODO: Why parseInt? Because source result is returned as a  string.
                            var icon= parseInt(source.result) ? '/static/icon_cancel.png' : '/static/icon_ok.png';
                            icon= '<img src="' + icon + '" width="16" height="16" />';
                            tableHtml.addRow([
                                icon,
                                'Source ' + source_name,
                                source.stats.transferred_bytes + '/' + source.stats.total_bytes + ' Bytes',
                            ]);
                        });
                    }
                );

            });

            $("#body").html(html.render());
        })
    };

    cmds.show_backup_result= function(params) {
        api('GetSessions', params, function(data) {
            console.log(data);
            if (data.error) return;

            mergeData(data);
            console.log(conf);

            var html= [];

            var html= new Html();
            html.add('<h1>' + conf.title + '</h1>');

            map(conf.baksets, function(bakset_name, bakset) {
                if (params.bakset && bakset_name != params.bakset) return;

                html.add('<h2>' + bakset.title + '</h2>');

                sortMap(bakset.sessions,
                    function(a, b) {
                        return strcmp(b.time.start, a.time.start);
                    },
                    function(session_id, session) {
                        session.title= fmtTime(session.time);
                        html.add('<h3>Session ' + session.title + '</h3>');

// source.stats.text ? source.stats.text.split('\n').join('<br>\n') : '',

                        var tableHtml= html.addTable();
                        map(session.sources, function(source_name, source) {

                            // TODO: Why parseInt? Because source result is returned as a  string.
                            var icon= parseInt(source.result) ? '/static/icon_cancel.png' : '/static/icon_ok.png';
                            icon= '<img src="' + icon + '" width="16" height="16" />';
                            tableHtml.addRow([
                                icon,
                                'Source ' + source_name,
                                source.fullname,
                                source.title,
                                source.path,
                                fmtTime(source.time),
                                source.stats.transferred_bytes + '/' + source.stats.total_bytes + ' Bytes',
                            ]);
                        });
                    }
                );

            });

            $("#body").html(html.render());
        })
    };

    cmds.test1= function(params) {

// kann mit fehlenden daten umgehen
// alternative: http://code.google.com/p/protovis-js/downloads/list


        $("#body").html('<div id="placeholder" style="width:600px;height:300px;"></div>');

        var d= [];
        map(conf.baksets, function(bakset_name, bakset) {
            var dd= [];
            var i= 0;
            map(bakset.sessions, function(session_id, session) {
                dd.push([ i++, session.saved ]);
            });
            d.push(dd);
        });
        console.log(d);

        $.plot($("#placeholder"), d);
    };


// ============================================================================
//      Live Event Handlers
// ============================================================================

    $('a').live('click', function() {
        console.log("Clicked:", $(this).attr('href'));

        var href= $(this).attr('href');
        
        // Not an internal link, pass on to browser
        if (href.substr(0, 1) != '#') return true;

        var paramsl= href.substr(1).split(/[:=]/);
        var cmd= paramsl.shift();
        var cmdFn= cmds[cmd];
        if (!cmdFn) {
            console.error('Command "' + cmd + '" not defined');
            return false;
        }

        var params= {};
        while (paramsl.length) {
            var key= paramsl.shift();
            params[key]= paramsl.shift();
        }

                        // Wenn true zurckgegeben wird, landets in der history und ist bookmarkable
        cmdFn(params);  // return cmdFn(params) ???
        return false;   // Oder evt abhaenging von nem params['omit_history'] ??
    });


// ============================================================================
//      Init
// ============================================================================

    var welcome= userTitle ? userTitle: userName;
    welcome= welcome ? '<br />Welcome, ' + welcome + '!<br /><a href="/logout?sid=' + sid + '">Log out</a>' : '';
    $('#head').html(
        '<div style="float: right">' + welcome + '</div>'
    );

    api('GetBaksets', null, function(data) {
        console.log(data);
        if (data.error) {
            // error stuff
            return;
        }

        mergeData(data);

        // TODO: conf.backsets.sort();

        var baksetHtml= [];
        for (var bakset_name in conf.baksets) {
            var bakset= conf.baksets[bakset_name];
            baksetHtml.push('<li><a href="#show_backup_result:bakset=' + bakset.name + '">' + bakset.title + ' (' + bakset.name + ')' + '</a></li>');
        }

        $("#sidebar").html( ''
            + '<h1>' + conf.title + '</h1>'
            + '<h2>Jobs</h2>'
            + '<ol>' + baksetHtml.join('') + '</ol>'
            + '<hr />'
            + '<p><a href="#test1">Test1</a></p>'
            + '<p><a href="#show_dashboard">Dashboard</a></p>'
        );

        cmds.show_dashboard();
    });


// TEST ----------------------- [[

    api('Test', null, function(data) {
        console.log(data);
    })


});
