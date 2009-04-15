
jQuery(function($) {

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
        
        jQuery.ajax({
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

    var welcome= userTitle ? userTitle: userName;
    welcome= welcome ? '<br />Welcome, ' + welcome + '!<br /><a href="/logout?sid=' + sid + '">Log out</a>' : '';
    $('#head').html(
        '<div style="float: right">' + welcome + '</div>'
    );

// TEST ----------------------- [[

    var confs= {};

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

        _mergeData(data.confs, confs);
    };

/*
    function mergeData(data) {
        for (var conf_file in data.confs) {
            var conf= data.confs[conf_file];
            if (!confs[conf_file]) {
                confs[conf_file]= conf;
                continue;
            }
            for (var bakset_name in conf.baksets) {
                var bakset= conf.baksets[bakset_name];
                if (!confs[conf_file]['baksets'][bakset_name]) {
                    confs[conf_file]['baksets']= bakset;
                    continue;
                }
                for (var session_dates in bakset.sessions) {
                    var session= bakset.sessions[session_dates];
                }
            }
        }
    };
*/

    api('GetBaksets', null, function(data) {
        console.log(data);
        if (data.error) {
            // error stuff
            return;
        }

        mergeData(data);

        var html= [];
        for (var conf_name in confs) {
            var conf= confs[conf_name];
            html.push('<li>' + conf.title + '</li>');

            for (var bakset_name in conf.baksets) {
                var bakset= conf.baksets[bakset_name];
                html.push('<li><a href="#show_backup_result:conf=' + conf_name + ':bakset=' + bakset.name + '">' + bakset.title + '</a></li>');
            }
        }

        $("#sidebar").html('<ol>' + html.join('') + '</ol>'
            + '<hr />'
            + '<a href="#test1">Test1</a>'
        );
    });

    api('Test', null, function(data) {
        console.log(data);
    })

// TEST ----------------------- ]]


    var cmds= {};

    var map= function(obj, fn) {
        for (var i in obj) fn(i, obj[i]);
    };

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

    var tableHtml= function(table) {
        var html= '';
        map(table, function(row_i, row) {
            html += '<tr><td>' + row.join('</td><td>') + '</td></tr>';
        });
        return '<table border=1>' + html + '<table>';
    };

    cmds.show_backup_result= function(params) {
        api('GetSessions', params, function(data) {
            console.log(data);
            if (data.error) return;

            mergeData(data);
            console.log(confs);

            var html= [];

            map(confs, function(conf_name, conf) {
                html.push('<h1>' + conf.title + '</h1>');

                map(conf.baksets, function(bakset_name, bakset) {
                    html.push('<h2>' + bakset.title + '</h2>');

                    map(bakset.sessions, function(session_id, session) {
                        html.push('<h3>Session ' + session.title + '</h3>');

                        var table= [];
                        map(session.sources, function(source_name, source) {
                            table.push(['Source ' + source_name, source.title,
                                // bakset.sources[source_name].path,
                                source.path,
                                fmtTime(source.time), source.stats]);
                        });
                        html.push(tableHtml(table));
                    });
                });
            });

            $("#body").html(html.join(''));
        })
    };

    cmds.test1= function(params) {

// kann mit fehlenden daten umgehen
// alternative: http://code.google.com/p/protovis-js/downloads/list

        $("#body").html('<div id="placeholder" style="width:600px;height:300px;"></div>');

$(function () {
    var d1 = [];
    for (var i = 0; i < 14; i += 0.5)
        d1.push([i, Math.sin(i)]);

    var d2 = [[0, 3], [4, 8], [8, 5], [9, 13]];

    // a null signifies separate line segments
    var d3 = [[0, 12], [7, 12], null, [7, 2.5], [12, 2.5]];

    $.plot($("#placeholder"), [ d1, d2, d3 ]);
});

        
    };

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

});
