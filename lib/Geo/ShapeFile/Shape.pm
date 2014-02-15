package Geo::ShapeFile::Shape;
use strict;
use warnings;
use Carp;
use Geo::ShapeFile;
use Geo::ShapeFile::Point;
use Tree::R;
use List::Util qw /min max/;

use parent qw /Geo::ShapeFile/;

our $VERSION = '2.55_001';

my $little_endian_sys = unpack 'b', (pack 'S', 1 );


sub new {
    my $proto = shift;
    my $class = ref ($proto) || $proto;
    my %args  = @_;

    my $self = {
        shp_content_length  => 0,
        source              => undef,
        shp_points          => [],
        shp_num_points      => 0,
        shp_parts           => [],
        shp_record_number   => undef,
        shp_shape_type      => undef,
        shp_num_parts       => 0,
        shp_x_min           => undef,
        shp_x_max           => undef,
        shp_y_min           => undef,
        shp_y_max           => undef,
        shp_z_min           => undef,
        shp_z_max           => undef,
        shp_m_min           => undef,
        shp_m_max           => undef,
        shp_data            => undef,
    };

    foreach (keys %args) {
        $self->{$_} = $args{$_};
    }

    bless $self, $class;

    return $self;
}

sub parse_shp {
    my $self = shift;

    $self->{source} = $self->{shp_data} = shift;

    $self->extract_ints('big', 'shp_record_number', 'shp_content_length');
    $self->extract_ints('little', 'shp_shape_type');

    my $parser = 'parse_shp_' . $self->type($self->{shp_shape_type});

    croak "Can't parse shape_type $self->{shp_shape_type}"
      if !$self->can($parser);

    $self->$parser();

    if (length($self->{shp_data})) {
        my $len = length($self->{shp_data});
        my $byte_plural = $len > 1 ? 's' : '';
        carp "$len byte$byte_plural remaining in buffer after parsing "
        . $self->shape_type_text()
        . ' #'
        . $self->shape_id();
    }
}

sub parse_shp_Null {
    my $self = shift;
}

# TODO - document this
sub add_point {
    my $self = shift;

    if(@_ == 1) {
        my $point = shift;
        if($point->isa('Geo::ShapeFile::Point')) {
            push @{$self->{shp_points}}, $point;
        }
    }
    else {
        my %point_opts = @_;

        push @{$self->{shp_points}}, Geo::ShapeFile::Point->new(%point_opts);
        $self->{shp_num_points}++;
    }
}

# TODO - document this
sub add_part {
    my $self = shift;

    push @{$self->{shp_parts}}, $self->{shp_num_parts}++;
}

# TODO - finish me
sub calculate_bounds {
    my $self = shift;

    my %bounds = $self->find_bounds($self->points);
    foreach (keys %bounds) {
        $self->{'shp_' . $_} = $bounds{$_};
    }
    return %bounds;
}

sub parse_shp_Point {
    my $self = shift;
    $self->extract_doubles('shp_X', 'shp_Y');
    $self->{shp_points} = [Geo::ShapeFile::Point->new(
        X => $self->{shp_X},
        Y => $self->{shp_Y},
    )];
    $self->{shp_num_points} = 1;
    $self->{shp_x_min} = $self->{shp_X};
    $self->{shp_x_max} = $self->{shp_X};
    $self->{shp_y_min} = $self->{shp_Y};
    $self->{shp_y_max} = $self->{shp_Y};
}
#  Point
# Double        X       // X coordinate
# Double        Y       // Y coordinate

sub parse_shp_PolyLine {
    my $self = shift;

    $self->extract_bounds();
    $self->extract_parts_and_points();
}
#  PolyLine
# Double[4]             Box         // Bounding Box
# Integer               NumParts    // Number of parts
# Integer               NumPoints   // Number of points
# Integer[NumParts]     Parts       // Index to first point in part
# Point[NumPoints]      Points      // Points for all parts

sub parse_shp_Polygon {
    my $self = shift;

    $self->extract_bounds();
    $self->extract_parts_and_points();
}
#  Polygon
# Double[4]          Box        // Bounding Box
# Integer            NumParts   // Number of Parts
# Integer            NumPoints  // Total Number of Points
# Integer[NumParts]  Parts      // Index to First Point in Part
# Point[NumPoints]   Points     // Points for All Parts

sub parse_shp_MultiPoint {
    my $self = shift;

    $self->extract_bounds();
    $self->extract_ints('little', 'shp_num_points');
    $self->extract_points($self->{shp_num_points}, 'shp_points');
}
#  MultiPoint
# Double[4]          Box        // Bounding Box
# Integer            NumPoints  // Number of Points
# Point[NumPoints]   Points     // The points in the set

sub parse_shp_PointZ {
    my $self = shift;

    $self->parse_shp_Point();
    $self->extract_doubles('shp_Z', 'shp_M');
    $self->{shp_points}->[0]->Z($self->{shp_Z});
    $self->{shp_points}->[0]->M($self->{shp_M});
}
#  PointZ
# Point +
# Double Z
# Double M

sub parse_shp_PolyLineZ {
    my $self = shift;

    $self->parse_shp_PolyLine();
    $self->extract_z_data();
    $self->extract_m_data();
}
#  PolyLineZ
# PolyLine +
# Double[2]             Z Range
# Double[NumPoints]     Z Array
# Double[2]             M Range
# Double[NumPoints]     M Array

sub parse_shp_PolygonZ {
    my $self = shift;

    $self->parse_shp_Polygon();
    $self->extract_z_data();
    $self->extract_m_data();
}
#  PolygonZ
# Polygon +
# Double[2]             Z Range
# Double[NumPoints]     Z Array
# Double[2]             M Range
# Double[NumPoints]     M Array

sub parse_shp_MultiPointZ {
    my $self = shift;

    $self->parse_shp_MultiPoint();
    $self->extract_z_data();
    $self->extract_m_data();
}
#  MultiPointZ
# MultiPoint +
# Double[2]         Z Range
# Double[NumPoints] Z Array
# Double[2]         M Range
# Double[NumPoints] M Array

sub parse_shp_PointM {
    my $self = shift;

    $self->parse_shp_Point();
    $self->extract_doubles('shp_M');
    $self->{shp_points}->[0]->M($self->{shp_M});
}
#  PointM
# Point +
# Double M // M coordinate

sub parse_shp_PolyLineM {
    my $self = shift;

    $self->parse_shp_PolyLine();
    $self->extract_m_data();
}
#  PolyLineM
# PolyLine +
# Double[2]             MRange      // Bounding measure range
# Double[NumPoints]     MArray      // Measures for all points

sub parse_shp_PolygonM {
    my $self = shift;

    $self->parse_shp_Polygon();
    $self->extract_m_data();
}
#  PolygonM
# Polygon +
# Double[2]             MRange      // Bounding Measure Range
# Double[NumPoints]     MArray      // Measures for all points

sub parse_shp_MultiPointM {
    my $self = shift;

    $self->parse_shp_MultiPoint();
    $self->extract_m_datextract_m_data();
}
#  MultiPointM
# MultiPoint
# Double[2]         MRange      // Bounding measure range
# Double[NumPoints] MArray      // Measures

sub parse_shp_MultiPatch {
    my $self = shift;

    $self->extract_bounds();
    $self->extract_parts_and_points();
    $self->extract_z_data();
    $self->extract_m_data();
}
# MultiPatch
# Double[4]           BoundingBox
# Integer             NumParts
# Integer             NumPoints
# Integer[NumParts]   Parts
# Integer[NumParts]   PartTypes
# Point[NumPoints]    Points
# Double[2]           Z Range
# Double[NumPoints]   Z Array
# Double[2]           M Range
# Double[NumPoints]   M Array

sub extract_bounds {
    my $self = shift;

    $self->extract_doubles(qw/shp_x_min shp_y_min shp_x_max shp_y_max/);
}

sub extract_ints {
    my $self = shift;
    my $end = shift;
    my @what = @_;

    my $template = ($end =~ /^l/i) ? 'V' :'N';

    $self->extract_and_unpack(4, $template, @what);
}

sub extract_count_ints {
    my $self = shift;
    my $count = shift;
    my $end = shift;
    my $label = shift;

    my $template = ($end =~ /^l/i) ? 'V' :'N';

    my $tmp = substr $self->{shp_data}, 0, ($count * 4), '';
    my @tmp = unpack $template . $count, $tmp;
    #my @tmp = unpack($template."[$count]",$tmp);

    $self->{$label} = [@tmp];
}

sub extract_doubles {
    my $self = shift;
    my @what = @_;
    my $size = 8;
    my $template = 'd';

    foreach ( @what ) {
        my $tmp = substr $self->{shp_data}, 0, $size, '';
        $self->{ $_ } = $little_endian_sys
            ? (unpack $template, $tmp )
            : (unpack $template, scalar reverse $tmp );
    }
}

sub extract_count_doubles {
    my $self = shift;
    my $count = shift;
    my $label = shift;

    my $tmp = substr $self->{shp_data}, 0, $count*8, '';
    my @tmp = $little_endian_sys
        ? (unpack 'd'.$count, $tmp )
        : (reverse unpack( 'd' . $count, scalar ( reverse( $tmp ) ) ) );

    $self->{$label} = [@tmp];
}

sub extract_points {
    my $self = shift;
    my $count = shift;
    my $label = shift;

    my $data = substr $self->{shp_data}, 0, $count * 16, '';

    my @ps = $little_endian_sys
        ? (unpack 'd*', $data )
        : (reverse unpack 'd*', scalar reverse $data );

    my @p = (); # points
    while(@ps) {
        my ($x, $y) = (shift @ps, shift @ps);
        push @p, Geo::ShapeFile::Point->new(X => $x, Y => $y);
    }
    $self->{$label} = [@p];
}

sub extract_and_unpack {
    my $self = shift;
    my $size = shift;
    my $template = shift;
    my @what = @_;

    foreach(@what) {
        my $tmp = substr $self->{shp_data}, 0, $size, '';
        if ( $template eq 'd' ) {
            $tmp = Geo::ShapeFile->byteswap( $tmp );
        }
        $self->{$_} = unpack $template, $tmp;
    }
}

sub num_parts { shift()->{shp_num_parts}; }
sub parts {
    my $self = shift;

    my $parts = $self->{shp_parts};

    return wantarray ? @{$parts || []} : $parts;
}

sub num_points { shift()->{shp_num_points}; }
sub points {
    my $self = shift;

    my $points = $self->{shp_points};

    return wantarray ? @{$points || []} : $points;
}

sub get_part {
    my $self  = shift;
    my $index = shift;

    croak 'index passed to get_part must be >0'
      if $index <= 0;

    $index -= 1; # shift to a 0 index

    #  $parts is an array of starting indexes in the $points array
    my $parts  = $self->parts;
    croak 'index exceeds number of parts'
      if $index > $#$parts;

    my $points = $self->points;
    my $beg    = $parts->[$index]   || 0;
    my $end    = $parts->[$index+1] || 0;  #  if we use 5.010 then we can use the // operator here
    $end -= 1;
    if ($end < 0) {
        $end = $#$points;
    }

    return wantarray ? @$points[$beg .. $end] : [@$points[$beg .. $end]];
}

sub shape_type {
    my $self = shift;
    return $self->{shp_shape_type};
}

sub shape_id {
    my $self = shift;
    return $self->{shp_record_number};
}

sub extract_z_data {
    my $self = shift;

    $self->extract_doubles('shp_z_min', 'shp_z_max');
    $self->extract_count_doubles($self->{shp_num_points}, 'shp_z_data');
    my @zdata = @{delete $self->{shp_z_data}};
    for (0 .. $#zdata) {
        $self->{shp_points}->[$_]->Z($zdata[$_]);
    }
}

sub extract_m_data {
    my $self = shift;

    $self->extract_doubles ('shp_m_min', 'shp_m_max');
    $self->extract_count_doubles($self->{shp_num_points}, 'shp_m_data');
    my @mdata = @{delete $self->{shp_m_data}};
    for (0 .. $#mdata) {
        $self->{shp_points}->[$_]->M($mdata[$_]);
    }
}

sub extract_parts_and_points {
    my $self = shift;

    $self->extract_ints('little', 'shp_num_parts', 'shp_num_points');
    $self->extract_count_ints($self->{shp_num_parts}, 'little', 'shp_parts');
    $self->extract_points($self->{shp_num_points}, 'shp_points');
}


#  these could be factory generated
sub x_min { shift()->{shp_x_min}; }
sub x_max { shift()->{shp_x_max}; }
sub y_min { shift()->{shp_y_min}; }
sub y_max { shift()->{shp_y_max}; }
sub z_min { shift()->{shp_z_min}; }
sub z_max { shift()->{shp_z_max}; }
sub m_min { shift()->{shp_m_min}; }
sub m_max { shift()->{shp_m_max}; }

sub has_point {
    my $self  = shift;
    my $point = shift;

    return 0 if !$self->bounds_contains_point($point);

    foreach my $check_pt ($self->points) {
        return 1 if $check_pt == $point;
    }

    return 0;
}

sub contains_point {
    my ( $self, $point, $index_res ) = @_;

    return $self->_contains_point_use_index ($point, $index_res)
      if $self->get_spatial_index || defined $index_res;

    return 0 if !$self->bounds_contains_point( $point );

    my $a = 0;
    my ( $x0, $y0 ) = ( $point->get_x, $point->get_y );

    #  one day we will track the bounds of the parts
    #  so we can more easily skip parts of multipart polygons
    my $num_parts = $self->num_parts;

    #  $x1, $x2, $y1 and $y2 are offsets from the point we are checking
    foreach my $part_num (1 .. $num_parts) {
        my $points = $self->get_part( $part_num );

        my $p_start = shift @$points;  #  $points is a copy, so no harm in shifting
        my $x1 = $p_start->get_x - $x0;
        my $y1 = $p_start->get_y - $y0;

        foreach my $p2 ( @$points ) {
            my $x2 = $p2->get_x - $x0;
            my $y2 = $p2->get_y - $y0;

            #  does the ray intersect the segment?
            if (($y2 >= 0) != ($y1 >= 0)) {
                my $isl = $x1 * $y2 - $y1 * $x2;
                if ( $y2 > $y1 ) {
                    if ($isl > 0) {
                        $a--;
                    }
                }
                else {
                    if ($isl < 0) {
                        $a++;
                    }
                }
            }
            ( $x1, $y1 ) = ( $x2, $y2 );
        }
    }

    return $a;
}

sub _contains_point_use_index {
    my ( $self, $point, $index_res ) = @_;

    return 0 if !$self->bounds_contains_point( $point );

    my $sp_index_hash = $self->get_spatial_index || $self->build_spatial_index ($index_res);

    my $a = 0;
    my ( $x0, $y0 ) = ( $point->get_x, $point->get_y );

    my @parts = $self->parts;
    my $num_parts = scalar @parts;

    #  $x1, $x2, $y1 and $y2 are offsets from the point we are checking
  PART_ID:
    foreach my $part_index (1 .. $num_parts) {
        #my $part_id = $parts[$part_index];
        my $sp_index = $sp_index_hash->{$part_index};

        my @results;
        $sp_index->query_point($x0, $y0, \@results);

        #  skip if not in this part's bounding box
        next PART_ID if !scalar @results;

        # segments spanning the index's bounding box
        for my $segment (@results) {

            my $x1 = $segment->[0]->get_x - $x0;
            my $y1 = $segment->[0]->get_y - $y0;
            my $x2 = $segment->[1]->get_x - $x0;
            my $y2 = $segment->[1]->get_y - $y0;

            #  does the ray intersect the segment?
            if (($y2 >= 0) != ($y1 >= 0)) {
                my $isl = $x1 * $y2 - $y1 * $x2;
                if ( $y2 > $y1 ) {
                    if ($isl > 0) {
                        $a--;
                    }
                }
                else {
                    if ($isl < 0) {
                        $a++;
                    }
                }
            }
        }
    }

    return $a;
}


#  We could trigger a build if undefined,
#  but save that for later.  
sub get_spatial_index {
    my $self = shift;

    return $self->{_spatial_indexes};
}

#  Add the polygon's segments to a spatial index
#  where the index boxes are as wide as the part
#  they are in.
#  The set of spatial indexes is a hash keyed by
#  the part ID.
#  $n is the number of boxes - need an automatic way of calculating, poss f(y_range / x_range)
sub build_spatial_index {
    my $self = shift;
    my $n    = shift || 10;

    croak 'Cannot build spatial index with negative number of boxes'
      if $n <= 0;

    my %sp_indexes;

    my @parts = $self->parts;

    my $part_id = 0;
    foreach my $part (@parts) {
        my $sp_index = Tree::R->new;
        $part_id ++;  #  parts are indexed base 1

        my %bounds = $self->_get_part_bounds ($part_id);

        my ($x_min, $x_max, $y_min, $y_max) = @bounds{qw /x_min x_max y_min y_max/};
        my $y_range = $y_max - $y_min;
        my $y_tol   = $y_range / 10000;
        $y_range   += 2 * $y_tol;
        $y_min     -= $y_tol;  #  make sure everything is inside the boxes - no edge sitters
        $y_max     += $y_tol;

        my $box_ht  = $y_range / $n;

        my @box_y_vals;
        my $y = $y_min;
        foreach my $i (1 .. $n) {
            push @box_y_vals, [$y, $y + $box_ht];
            $y += $box_ht;
        }

        #  need to calculate the bounds for each part if more than one
        if (!defined $x_min) {
            my %bounds = $self->_get_part_bounds ($part);
            $x_min = $bounds{x_min};
            $x_max = $bounds{x_max};
        }

        my $segments = $self->get_segments ($part_id);

        foreach my $segment (@$segments) {
            my $y0 = $segment->[0]->get_y;
            my $y1 = $segment->[1]->get_y;

            #  reverse them if needed
            if ($y1 < $y0) {
                ($y0, $y1) = ($y1, $y0);
            }

            #  add the segment to each box it intersects
            my $in_box = 0;
          BOX:
            foreach my $bnd (@box_y_vals) {
                my $y_min = $bnd->[0];
                my $y_max = $bnd->[1];

                #  skip if we don't span this box
                if ($y1 <  $y_min || $y0 >= $y_max) {
                    last BOX if $in_box;  #  we have moved out
                    next BOX;             #  or try the next one
                }

                #  more tweaking would involve getting the
                #  min and max X across the segments to define each box
                my @bbox = ($x_min, $y_min, $x_max, $y_max);
                $sp_index->insert($segment, @bbox);
                $in_box++;
            }
            #print "$part_id " . scalar @$segments . " $in_box\n";
        }

        #  debug checks
        #my @results = ();
        #$sp_index->query_completely_within_rect(0, 0, 10**8, 10**8, \@results);
        #my %ex;
        #use List::MoreUtils qw /uniq/;
        #my @uniq = uniq @results;
        #print scalar @results . ' ' . (scalar @$segments) . ' ' . scalar @uniq . "\n";

        #  clear the bounds
        ($x_min, $x_max) = (undef, undef);

        $sp_indexes{$part_id} = $sp_index;
    }

    $self->{_spatial_indexes} = \%sp_indexes;

    return wantarray ? %sp_indexes : \%sp_indexes;
}

sub _get_part_bounds {
    my $self = shift;
    my $part = shift;

    my $points = $self->get_part($part);

    my $pt1 = shift @$points;
    my ($x_min, $y_min) = ($pt1->get_x, $pt1->get_y);
    my ($x_max, $y_max) = ($x_min, $y_min);

    foreach my $pt (@$points) {
        my $x = $pt->get_x;
        my $y = $pt->get_y;

        $x_min = min ($x_min, $x);
        $y_min = min ($y_min, $y);
        $x_max = max ($x_max, $x);
        $y_max = max ($y_max, $y);
    }

    my %bounds = (
        x_min => $x_min,
        x_max => $x_max,
        y_min => $y_min,
        y_max => $y_max,
    );

    return wantarray ? %bounds : \%bounds;
}

sub get_segments {
    my $self = shift;
    my $part = shift;

    my $points = $self->get_part($part);

    my @segments;
    foreach my $i (0 .. $#$points - 1) {
        push @segments, [$points->[$i], $points->[$i+1]];
    }

    return wantarray ? @segments : \@segments;
}

sub vertex_centroid {
    my $self = shift;
    my $part = shift;

    my ($cx, $cy) = (0, 0);

    my @points = ();
    if ($part) {
        @points = $self->get_part($part);
    }
    else {
        @points = $self->points;
    }

    foreach (@points) {
        $cx += $_->X;
        $cy += $_->Y;
    }

    Geo::ShapeFile::Point->new(
        X => $cx / @points,
        Y => $cy / @points,
    );
}
*centroid = \&vertex_centroid;

sub area_centroid {
    my ( $self, $part ) = @_;

    my ( $cx, $cy ) = ( 0, 0 );
    my $A = 0;

    my (@points, @parts);

    if ( defined $part ) {
        @parts = ( $part );
    }
    else {
        @parts = (1 .. $self->num_parts);
    }

    for my $part ( @parts ) {
        my ( $p0, @pts )  = $self->get_part( $part );
        my ( $x0, $y0 )   = ( $p0->X, $p0->Y );
        my ( $x1, $y1 )   = ( 0, 0 );
        my ( $cxp, $cyp ) = ( 0, 0 );
        my $Ap = 0;

        for ( @pts ) {
            my $x2 = $_->X - $x0;
            my $y2 = $_->Y - $y0;
            $Ap  += ( my $a = $x2*$y1 - $x1*$y2 );
            $cxp += $a * ( $x2 + $x1 ) / 3;
            $cyp += $a * ( $y2 + $y1 ) / 3;
            ( $x1, $y1 ) = ( $x2, $y2 );
        }

        $cx += $Ap * $x0 + $cxp;
        $cy += $Ap * $y0 + $cyp;
        $A += $Ap;
    }

    return Geo::ShapeFile::Point->new(
        X => $cx / $A,
        Y => $cy / $A,
    );
}

sub dump {
    my $self = shift;

    my $return = '';

    #$self->points();
    #$self->get_part();
    #$self->x_min, x_max, y_min, y_max, z_min, z_max, m_min, m_max

    $return .= sprintf
        "Shape Type: %s (id: %d)  Parts: %d   Points: %d\n",
        $self->shape_type_text(),
        $self->shape_id(),
        $self->num_parts(),
        $self->num_points();

    $return .= sprintf
        "\tX bounds(min=%s, max=%s)\n",
        $self->x_min(),
        $self->x_max();

    $return .= sprintf
        "\tY bounds(min=%s, max=%s)\n",
        $self->y_min(),
        $self->y_max();

    if (defined $self->z_min() && defined $self->z_max()) {
        $return .= sprintf
            "\tZ bounds(min=%s, max=%s)\n",
            $self->z_min(),
            $self->z_max();
    }

    if (defined $self->m_min() && defined $self->m_max()) {
        $return .= sprintf
            "\tM bounds(min=%s, max=%s)\n",
            $self->m_min(),
            $self->m_max();
    }

    for (1 .. $self->num_parts()) {
        $return .= "\tPart $_:\n";
        foreach ($self->get_part($_)) {
            $return .= "\t\t$_\n";
        }
    }

    $return .= "\n";

    return $return;
}

1;
__END__
=head1 NAME

Geo::ShapeFile::Shape - Geo::ShapeFile utility class.

=head1 SYNOPSIS

  use Geo::ShapeFile::Shape;

  my $shape = Geo::ShapeFile::Shape->new;
  $shape->parse_shp($shape_data);

=head1 ABSTRACT

  This is a utility class for L<Geo::ShapeFile> that represents shapes.

=head1 DESCRIPTION

This is the Geo::ShapeFile utility class that actually contains shape data
for an individual shape from the shp file.

=head2 EXPORT

None by default.

=head1 METHODS

=over 4

=item new()

Creates a new Geo::ShapeFile::Shape object, takes no arguments and returns
the created object.  Normally L<Geo::ShapeFile> does this for you when you call
its get_shp_record() method, so you shouldn't need to create a new object.
(Eventually this module will have support for _creating_ shapefiles rather
than just reading them, then this method will become important.

=item num_parts()

Returns the number of parts that make up this shape.

=item num_points()

Returns the number of points that make up this shape.

=item points()

Returns an array of Geo::ShapeFile::Point objects that contains all the points
in this shape.  Note that because a shape can contain multiple segments, which
may not be directly connected, you probably don't want to use this to retrieve
points which you are going to plot.  If you are going to draw the shape, you
probably want to use get_part() to retrieve the individual parts instead.

=item get_part($part_index);

Returns the specified part of the shape.  This is the information you want if
you intend to draw the shape.  You can iterate through all the parts that make
up a shape like this:

  for(1 .. $obj->num_parts) {
    my $part = $obj->get_part($_);
    # ... do something here, draw a map maybe
  }

=item shape_type()

Returns the numeric type of this shape, use Geo::ShapeFile::type() to determine
the human-readable name from this type.

=item shape_id()

Returns the id number for this shape, as contained in the shp file.

=item x_min() x_max() y_min() y_max()

=item z_min() z_max() m_min() m_max()

Returns the minimum/maximum ranges of the X, Y, Z, or M values for this shape,
as contained in it's header information.

=item has_point($point)

Returns true if the point object provided matches one of the points in the shape.  Note
that this does a simple comparison with the points that make up the shape, it
will not find a point that falls along a vertex between two points in the
shape.  See the L<Geo::ShapeFile::Point> documentation for a note about how
to exclude Z and/or M data from being considered when matching points.

=item contains_point($point);

Returns true if the specified point falls in the interior of this shape
and false if the point is outside the shape.  Return value is unspecified
if the point is one of the vertices or lies on some segment of the
bounding polygon.

Note that the return value is actually a winding-number computed ignoring
Z and M fields and so will be negative if the point is contained within a
shape winding the wrong way.

=item get_segments($part)

Returns an array consisting of array hashes, which contain the points for
each segment of a multi-segment part.

=item vertex_centroid( $part );

Returns a L<Geo::ShapeFile::Point> that represents the calculated centroid
of the shapes vertices.  If given a part index, calculates just for that
part, otherwise calculates it for the entire shape. See L</centroid> for
more on vertex_centroid vs area_centroid.

=item area_centroid( $part );

Returns a L<Geo::ShapeFile::Point> that represents the calculated area
centroid of the shape.  If given a part index, calculates just for that
part, otherwise calculates it for the entire shape. See L</centroid> for
more on vertex_centroid vs area_centroid.

=item centroid($part)

For backwards-compatibility reasons, centroid() is currently an alias to
vertex_centroid(), although it would probably make more sense for it to
point to area_centroid().  To avoid confusion (and possible future
deprecation), you should avoid this and use either vertex_centroid or
area_centroid.

=item dump()

Returns a text dump of the object, showing the shape type, id number, number
of parts, number of total points, the bounds for the X, Y, Z, and M ranges,
and the coordinates of the points in each part of the shape.

=back

=head1 REPORTING BUGS

Please send any bugs, suggestions, or feature requests to
  L<https://github.com/shawnlaffan/Geo-ShapeFile/issues>.

=head1 SEE ALSO

L<Geo::ShapeFile>

=head1 AUTHOR

Jason Kohles, E<lt>email@jasonkohles.comE<gt>

Shawn Laffan, E<lt>shawnlaffan@gmail.comE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright 2002-2013 by Jason Kohles

Copyright 2014 by Shawn Laffan

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
