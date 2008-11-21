#!/usr/bin/perl

package GraphViz::PrettySVG;

use strict;
use warnings;

use Data::Dumper;
use GD::Simple;
use XML::Twig;
use Math::Polygon;
use Math::Polygon::Transform;
use File::Temp qw( tempfile );

# use Data::Dumper;

our $VERSION = '0.01';

use Carp ();
local $SIG{__WARN__} = \&Carp::cluck;
local $SIG{__DIE__} = \&Carp::cluck;

=pod

=head1 NAME

GraphViz::PrettySVG - Spice up SVGs coming out of graphviz's dot

=head1 SYNOPSIS

#use FindBin qw($Bin);
#use lib $Bin;
use GraphViz::PrettySVG;

my $oPrettySvg= new GraphViz::PrettySVG(
        font_size_factor => 0.81,
        shadow => 'simulate',
    );
print $pPrettySvg->getPrettySVG("structure.dot");

=head1 BUGS

* Only works with dot. neato et al. are ignored...
* Many parameters still hard coded
* simulated shadow is buggy for rounded edges

=cut

sub new {
    my $class= shift;
    my %hArgs= @_;

    # See graphviz source, in ./plugin/core/gvrender_core_svg.c it says:
    # /* FIXME - even inkscape requires a magic correction to fontsize.  Why?  */
    # If they don't know, how should I?

    my $self= {
        FONT_SIZE_FACTOR => $hArgs{'font_size_factor'} || 0.81,
        SHADOW => $hArgs{'shadow'} || 'simulate',
    };

    # print STDERR Dumper(\%hArgs);

    bless $self, $class;
    return $self;
}

# our $font_size_factor= 0.81;
# our $use_shadow= 1;
# http://cpan.uwinnipeg.ca/htdocs/GD/GD/Simple.pm.html
# my $colors= GD::Simple->color_names;
# print Dumper($colors); die;
# inkscape -D -e output.png map.svg

our $grad_id;
our %grads= ();

sub str_to_hsv {
    my $color= shift;

    $color =~ s/^s+//;
    $color =~ s/s+$//;

    my $colors= GD::Simple->color_names;

    if ($colors->{$color}) {
        my $rgb= $colors->{$color};
        return GD::Simple->RGBtoHSV($rgb->[0], $rgb->[1], $rgb->[2]);
    }
    if ($color =~ /^#([0-9a-f])([0-9a-f])([0-9a-f])$/i) {
        return GD::Simple->RGBtoHSV(hex("$1$1"), hex("$2$2"), hex("$3$3"));
    }
    if ($color =~ /^#([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])$/i) {
        return GD::Simple->RGBtoHSV(hex($1), hex($2), hex($3));
    }
    return (0, 0, 0);
}

sub rgb_to_str {
    my @rgb= @_;
    return sprintf('#%02x%02x%02x', $rgb[0], $rgb[1], $rgb[2]);
}

sub get_style {
    my $g= shift;

    my %style= ();
    for (split(/\s*;\s*/, $g->att('style'))) {
        die unless /^(.*?):(.*)$/;
        $style{$1}= $2;
    }
    return %style;
}

sub set_style {
    my $g= shift;
    my %style= @_;

    my $s_style= "";
    for (keys %style) {
        $s_style .= "$_:" . $style{$_} . ";";
    }
    $g->set_att('style', $s_style);
}

sub _shadow_coord {
    my ($centerx, $centery, $f0, $x, $y)= @_;

    $x= ($x - $centerx) * $f0 + $centerx;
    $y= ($y - $centery) * $f0 + $centery;

    # Small vertical offset
    return sprintf(" %.2f,%.2f", $x, $y + 1);
}

sub _shadow_ring_part {
    my ($rec, $centerx, $centery, $p0x, $p0y, $p1x, $p1y, $f0, $f)= @_;
    # my ($rec, $p0x, $p0y, $p1x, $p1y, $f)= @_;

    my $mx= ($p0x + $p1x) / 2;
    my $my= ($p0y + $p1y) / 2;

    $mx= ($mx - $centerx) * $f + $centerx;
    $my= ($my - $centery) * $f + $centery;

    my $s= _shadow_coord($centerx, $centery, $f0, $mx, $my);

    # my $rf= 300;
    # return $s if ($p1x - $p0x) * ($p1x - $p0x) < $rf && ($p1y - $p0y) * ($p1y - $p0y) < $rf; 

    my $len= sqrt(($p1x - $p0x) * ($p1x - $p0x) + ($p1y - $p0y) * ($p1y - $p0y));
    return $s if $len < 50;

    if ($rec) {
        $f= (3 + $f) / 4;
        $s= _shadow_ring_part($rec-1, $centerx, $centery, $p0x, $p0y, $mx, $my, $f0, $f)
            . $s
            . _shadow_ring_part($rec-1, $centerx, $centery, $mx, $my, $p1x, $p1y, $f0, $f)
        ;
    }
    return $s;
}

sub _shadow_ring {
    my ($g, $poly, $f0, $f, $color)= @_;

    my @bbox= $poly->bbox;

    if (!defined($bbox[0])) {
        print Dumper($poly);
        die;
    }

    my $centerx= ($bbox[0] + $bbox[2]) / 2;
    my $centery= ($bbox[1] + $bbox[3]) / 2;

    my $diag= sqrt( ($bbox[3] - $bbox[1]) * ($bbox[3] - $bbox[1]) + ($bbox[2] - $bbox[0]) * ($bbox[2] - $bbox[0]) );

    my $opacity= sprintf("%.2f", 2 / $diag);    # can't find round() .. :-(
    $opacity= 0.020 if $opacity > 0.020;
    $opacity= 0.013 if $opacity < 0.013;

    # print "DIAG: $diag\n";

    my $points= $poly->points;

    my $s= '';
    for (my $i= 0; $i <= $#{ $points }; $i++) {

        my $mx= $points->[$i][0];
        my $my= $points->[$i][1];

        $mx= ($mx - $centerx) * $f + $centerx;
        $my= ($my - $centery) * $f + $centery;

    #    $s .= _shadow_coord($centerx, $centery, $f0, $mx, $my);

        if ($i < $#{ $points }) {

            my $x2= $points->[$i+1][0];
            my $y2= $points->[$i+1][1];

            $x2= ($x2 - $centerx) * $f + $centerx;
            $y2= ($y2 - $centery) * $f + $centery;

            $s .= _shadow_ring_part(8, $centerx, $centery, $mx, $my, $x2, $y2, $f0, $f);
        }
    }

    my $debug= '';
    # $debug= 'x-';

    $color= 'black' unless $debug;

    $s= qq(<polygon style="fill:$color; stroke:none;" points="$s"/>);
    $s = qq(<g style="${debug}fill-opacity: $opacity;">$s</g>);

    my $elt= parse XML::Twig::Elt($s);
    $elt->paste('before', $g); 
}

sub add_shadow {
    my $self= shift;
    my $g= shift;

    return unless $self->{SHADOW} eq 'simulate';

    my $poly= get_points_as_poly($g);
    my $size= 0.82;
    my $dist= 1.26;
    for (0..3) {
        _shadow_ring($g, $poly, $size, $dist, 'green');
        $dist -= .02;
        _shadow_ring($g, $poly, $size, $dist, 'red');
        $dist -= .02;
    }
}

use GD::Polyline;

sub add_shadow_new {
    my $self= shift;
    my $g= shift;

    my $polyline = new GD::Polygon;

    my @points= get_points($g);
    for my $point (@points) {
        $polyline->addPt($point->[0], $point->[1]);
    }

    $polyline->deletePt($polyline->length-1);

    my $spline = $polyline->addControlPoints->toSpline;

    @points = $spline->vertices;

    my $poly= Math::Polygon->new(points => \@points);


    my $color= 'red';
    my $s= points_to_str($poly->points);
    my $opacity= 1;

    $s= qq(<polygon style="fill:$color; stroke:none;" points="$s"/>);
    $s = qq(<g style="fill-opacity: $opacity;">$s</g>);

    my $elt= parse XML::Twig::Elt($s);
    $elt->paste('before', $g); 

    print STDERR Dumper($poly);

}

sub poly_resize {
    my $poly= shift;
    my $scale= shift;

    my @bbox= $poly->bbox;
    my $centerx= ($bbox[0] + $bbox[2]) / 2;
    my $centery= ($bbox[1] + $bbox[3]) / 2;

    return $poly->resize(scale => $scale, center => [$centerx, $centery]);
}

sub grad_id {
    my $id= shift;
    return $id unless $id =~ /[^\-a-zA-Z0-9]/;
    $main::grad_id++;
    # print "GRAD_ID! " . $main::grad_id . "!\n";
    return "grad" . ($main::grad_id++);
}

sub get_points {
    my $g= shift;

    my @points= ();
    my $s_points= $g->att('points');
    $s_points =~ s/^\s+//;
    $s_points =~ s/\s+$//;
    for (split(/\s+/, $s_points)) {
        push @points, [ split(/\s*,\s*/) ];
    }
    return @points;
}

sub get_points_as_poly {
    my $g= shift;

    my @points= get_points($g);
    return Math::Polygon->new(points => \@points);
}

sub points_to_str {
    my @points= @_;

    my $s_points= '';
    for my $point (@points) {
        $s_points .= sprintf(" %.2f,%.2f", $point->[0], $point->[1]);
    }
    return $s_points;
}

sub add_highlight {
    my $self= shift;
    my $g= shift;

    my $poly= get_points_as_poly($g);
    $poly= poly_resize($poly, 0.85);

    my $s_points= points_to_str($poly->points);

    my $s = qq(<polygon style="fill:url(#poly-highlight); stroke: none;" points="$s_points"/>);

    my $elt= parse XML::Twig::Elt($s);
    $elt->paste('after', $g); 
}

sub round_rectangles {
    my $g= shift;

    my @points= get_points($g);

    # check if it's a rectangle
    return unless scalar @points == 5;

    my $x0= $points[2][0];
    my $y0= $points[2][1];
    my $x1= $points[0][0];
    my $y1= $points[0][1];

    my $epsilon = 0.1;
    return unless abs($x0 - $points[1][0]) < $epsilon;
    return unless abs($y0 - $points[3][1]) < $epsilon;
    return unless abs($x1 - $points[3][0]) < $epsilon && abs($x1 - $points[4][0]) < $epsilon;
    return unless abs($y1 - $points[1][1]) < $epsilon && abs($y1 - $points[4][1]) < $epsilon;

    ($x0, $x1)= ($x1, $x0) if $x0 > $x1;
    ($y0, $y1)= ($y1, $y0) if $y0 > $y1;

    my $r= 6;
    $r= ($x1 - $x0) / 3 if $r > $x1 - $x0;
    $r= ($y1 - $y0) / 3 if $r > $y1 - $y0;

    return if $r < 3;

    # my @edge= ([0, -$r], [$r/4, -$r/2], [$r*3/4, -$r/3], [$r, 0]);
    my @edge= ([$r, 0], [$r * 0.7, -$r * 0.1], [$r * 0.35, -$r * 0.35], [$r * 0.1, -$r * 0.7], [0, -$r]);

    @points= ();

    map { push @points, [$x0 + $_->[0], $y0 - $_->[1]] } @edge;
    map { push @points, [$x0 + $_->[0], $y1 + $_->[1]] } reverse @edge;
    map { push @points, [$x1 - $_->[0], $y1 + $_->[1]] } @edge;
    map { push @points, [$x1 - $_->[0], $y0 - $_->[1]] } reverse @edge;

    push @points, $points[0];

    # print STDERR Dumper( \@points );
    # print STDERR points_to_str(@points);

    $g->set_att('points', points_to_str(@points));
}

sub modify_node_color {
    my $self= shift;
    my $g= shift;

    my %style= get_style($g);

    $style{'fill'}= 'white' if $style{'fill'} eq 'none';

    if ($style{'stroke'} ne 'none') {
        if ($style{'fill'} eq 'white') {
            my $grad_id= grad_id($style{'stroke'});
            $grads{'stroke-' . $grad_id}= $style{'stroke'};
            $style{'stroke'}= 'url(#stroke-' . $grad_id . ')';
        }
        else {
            my $grad_id= grad_id($style{'fill'});
            $grads{'stroke-' . $grad_id}= $style{'fill'};
            $style{'stroke'}= 'url(#stroke-' . $grad_id . ')';
        }
    }

    my $grad_id= grad_id($style{'fill'});
    $grads{'fill-' . $grad_id}= $style{'fill'};
    $style{'fill'}= 'url(#fill-' . $grad_id . ')';

    set_style($g, %style);
}

sub modify_cluster_color {
    my $self= shift;
    my $g= shift;

    my %style= get_style($g);

    # print STDERR Dumper(\%style);

    $style{'stroke'}= 'white' if $style{'stroke'} eq 'black';

    my @hsv= str_to_hsv($style{'stroke'});

    $hsv[1]= 128 if $hsv[1] > 128;
    $hsv[2]= 255 if $hsv[1];
    $style{'stroke'}= rgb_to_str(hsv_to_rgb(@hsv));

    # print STDERR Dumper(\%style);

    my $grad_id= grad_id($style{'stroke'});
    $grads{'cfill-' . $grad_id}= $style{'stroke'};
    $style{'fill'}= 'url(#cfill-' . $grad_id . ')';

    $hsv[1]= 32 if $hsv[1] > 32;
    $hsv[2]= 255 if $hsv[1];
    $style{'stroke'}= rgb_to_str(hsv_to_rgb(@hsv));

    # print STDERR Dumper(\%style);

    set_style($g, %style);
}

sub convert_ellipse_to_polygon {

    my $g= shift;

    my $cx= $g->att("cx");
    my $cy= $g->att("cy");
    my $rx= $g->att("rx");
    my $ry= $g->att("ry");

    # TODO: make $delta depentent on $rx/$ry

    my $s_points= '';
    my $PI= 3.14159265;
    for (my $angle= 0; $angle < 360; $angle += 10) {
        my $x= $cx + sin($angle * $PI / 180) * $rx;
        my $y= $cy + cos($angle * $PI / 180) * $ry;
        $s_points .= sprintf(" %.2f,%.2f", $x, $y);
    }

    $g->set_tag("polygon");
    $g->set_att("points", $s_points);
    $g->del_att("cx");
    $g->del_att("cy");
    $g->del_att("rx");
    $g->del_att("ry");
}

sub modify_graph {
    my $self= shift;
    my $root= shift;

    my @elts= $root->get_xpath("//[\@class=\"graph\"]/polygon");
    for my $g (@elts) {
        my %style= get_style($g);

        # TODO: check color

        $style{'fill'}= 'url(#graph-background)';
        set_style($g, %style);
    }
}

sub modify_edges {
    my $self= shift;
    my $root= shift;

    my @elts= $root->get_xpath("//[\@class=\"edge\"]/path");
    for my $g (@elts) {
        my %style= get_style($g);
        $style{'stroke-width'}= 4 if defined $style{'stroke-width'} && $style{'stroke-width'} == 2;
        set_style($g, %style);
    }
}

sub modify_nodes {
    my $self= shift;
    my $root= shift;
    my @elts;

    @elts= $root->get_xpath("//[\@class=\"node\"]/polygon");
    for my $g (@elts) {
        round_rectangles($g);
    }

    @elts= $root->get_xpath("//[\@class=\"node\"]/ellipse");
    for my $g (@elts) {
        convert_ellipse_to_polygon($g);
    }

    @elts= $root->get_xpath("//[\@class=\"node\"]/polygon");
    for my $g (@elts) {
        $self->modify_node_color($g);
        $self->add_shadow($g);
        $self->add_highlight($g);
    }
}

sub modify_cluster {
    my $self= shift;
    my $root= shift;

    my @elts= $root->get_xpath("//[\@class=\"cluster\"]/polygon");
    for my $g (@elts) {
        $self->modify_cluster_color($g);
        $self->add_shadow($g);
    }
}

sub modify_text {
    my $self= shift;
    my $root= shift;

    # TODO: Don't substitute for Postscript output?

    my %subst= (
        "URW Gothic L" => "Avant Garde, AvantGarde, URW Gothic L, sans-serif",
        "URW Bookman L" => "Bookman, URW Bookman L, serif",
        "Nimbus Mono L" => "Courier New, Courier, Nimbus Mono L, monospace",
        "Nimbus Sans L" => "Arial, Helvetica, Nimbus Sans L, sans-serif",
        "Century Schoolbook L" => "New Century Schoolbook, Century Schoolbook, Century Schoolbook L, serif",
        "URW Palladio L" => "Palatino, Book Antiqua, URW Palladio L, serif",
        "Standard Symbols L" => "Symbol, Standard Symbols L",
        "Nimbus Roman No9 L" => "Times New Roman, Times, Nimbus Roman No9 L, serif",
        "URW Chancery L" => "Zapf Chancery, URW Chancery L, cursive",
        "Dingbats" => "Dingbats",
    );

    my @elts= $root->get_xpath("//text");
    for my $g (@elts) {
        my %style= get_style($g);
        $style{'font-family'}= $subst{$style{'font-family'}} if defined $style{'font-family'} && $subst{$style{'font-family'}};
        if (defined $style{'font-size'} && $style{'font-size'} =~ /^(\d*(\.\d+))?([a-z]*)$/i) {
            $style{'font-size'}= sprintf("%.2f%s", $1 * $self->{FONT_SIZE_FACTOR}, $3);
        }
        if (defined $style{'font'}) {
            $style{'font-family'}= $style{'font'};
            delete $style{'font'};
        }
        set_style($g, %style);
    }
}

sub hsv_to_rgb {
    my (@hsv)= @_;
    $hsv[1]= 0 if $hsv[1] < 0;
    $hsv[1]= 255 if $hsv[1] > 255;
    $hsv[2]= 0 if $hsv[2] < 0;
    $hsv[2]= 255 if $hsv[2] > 255;
    return GD::Simple->HSVtoRGB(@hsv);
}

sub add_grads {
    my $self= shift;
    my $root= shift;

    for my $grad (keys %grads) {
    
        $grad =~ /^(.*?)-(.*)$/ or die;
        my ($type, $grad_id)= ($1, $2);
    
        my $color= $grads{$grad};
        my @hsv= str_to_hsv($color);
    
        my @rgb1= hsv_to_rgb($hsv[0], $hsv[1] * 2, $hsv[2]);
        my @rgb2= hsv_to_rgb($hsv[0], $hsv[1] / 6, $hsv[2] * 2);
    
        if ($type eq 'stroke') {
            @rgb1= hsv_to_rgb($hsv[0], $hsv[1] / 3, 150-16);
            @rgb2= hsv_to_rgb($hsv[0], $hsv[1] * 3, 150+16);
        }
        if ($type eq 'cfill') {

            @rgb1= hsv_to_rgb($hsv[0], $hsv[1] * 1.1, $hsv[2] + 30);
            @rgb2= hsv_to_rgb($hsv[0], $hsv[1] - 30, $hsv[2] - (255- $hsv[1]) * 0.1);

#            @rgb1= hsv_to_rgb($hsv[0], $hsv[1], $hsv[2] * 1.2);
#            @rgb2= hsv_to_rgb($hsv[0], $hsv[1] - 10, $hsv[2] * 0.8);
        }
    
        my $s_color1= rgb_to_str(@rgb1);
        my $s_color2= rgb_to_str(@rgb2);

        if ($type eq 'cfill') {
            parse XML::Twig::Elt(qq(
                <defs>
                    <linearGradient id="$type-$grad_id" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="10%" style="stop-color:$s_color2; stop-opacity: 1;"/>
                        <stop offset="20%" style="stop-color:$s_color1; stop-opacity: 1;"/>
                        <stop offset="50%" style="stop-color:$s_color2; stop-opacity: 1;"/>
                        <stop offset="70%" style="stop-color:$s_color1; stop-opacity: 1;"/>
                        <stop offset="95%" style="stop-color:$s_color2; stop-opacity: 1;"/>
                    </linearGradient>
                </defs>
            ))->paste('first_child', $root); 
        }
        else {
            parse XML::Twig::Elt(qq(
                <defs>
                    <linearGradient id="$type-$grad_id" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:$s_color2; stop-opacity: 1;"/>
                        <stop offset="70%" style="stop-color:$s_color1; stop-opacity: 1;"/>
                        <stop offset="95%" style="stop-color:$s_color2; stop-opacity: 1;"/>
                    </linearGradient>
                </defs>
            ))->paste('first_child', $root); 
        }

    };

    parse XML::Twig::Elt(qq(
        <defs>
            <linearGradient id="poly-highlight" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" style="stop-color:white; stop-opacity: 0.8;"/>
                <stop offset="40%" style="stop-color:white; stop-opacity: 0;"/>
            </linearGradient>
        </defs>
    ))->paste('first_child', $root); 

    parse XML::Twig::Elt(qq(
        <defs>
            <linearGradient id="graph-background" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" style="stop-color:#d0ffff; stop-opacity: 1;"/>
                <stop offset="60%" style="stop-color:white; stop-opacity: 1;"/>
            </linearGradient>
        </defs>
    ))->paste('first_child', $root); 
}

sub getPrettySVG {
    my $self= shift;
    my $file= shift;

    return '' unless $file;

    my $twig= new XML::Twig();

    if ($file =~ /\.dot$/) {
        my (undef, $svgfile)= tempfile();
        `dot -Tsvg $file > $svgfile`;   # unless -e "$svgfile";
        $twig->parsefile($svgfile); 
    }
    elsif ($file =~ /\.svg$/) {
        $twig->parsefile($file); 
    }
    else {
        $twig->parse($file);
    }

    my $root= $twig->root;

    %grads= ();

    $self->modify_graph($root);
    $self->modify_edges($root);
    $self->modify_nodes($root);
    $self->modify_cluster($root);
    $self->modify_text($root);

    $self->add_grads($root);

    return $twig->sprint;
}

1;
