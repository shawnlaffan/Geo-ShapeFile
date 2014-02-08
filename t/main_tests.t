#  tests for Geo::ShapeFile

use Test::More;
use strict;
use warnings;
use rlib '../lib', './lib';

BEGIN {
    use_ok('Geo::ShapeFile');
    use_ok('Geo::ShapeFile::Shape');
    use_ok('Geo::ShapeFile::Point');
};

#  should use $FindBin::bin for this
my $dir = "t/test_data";

note "Testing Geo::ShapeFile version $Geo::ShapeFile::VERSION\n";

use Geo::ShapeFile::TestHelpers;

test_shapepoint();
test_files();
test_empty_dbf();

done_testing();

###########################################

sub test_shapepoint {
    my @test_points = (
        ['1','1'],
        ['1000000','1000000'],
        ['9999','43525623523525'],
        ['2532525','235253252352'],
        ['2.1352362','1.2315216236236'],
        ['2.2152362','1.2315231236236','1134'],
        ['2.2312362','1.2315236136236','1214','51321'],
        ['2.2351362','1.2315236216236','54311'],
    );

    foreach my $pts (@test_points) {
        my ($x,$y,$m,$z) = @$pts;
        my $txt;
    
        if(defined $z && defined $m) {
            $txt = "Point(X=$x,Y=$y,Z=$z,M=$m)";
        }
        elsif (defined $m) {
            $txt = "Point(X=$x,Y=$y,M=$m)";
        }
        else {
            $txt = "Point(X=$x,Y=$y)";
        }
        my $p1 = Geo::ShapeFile::Point->new(X => $x, Y => $y, Z => $z, M => $m);
        my $p2 = Geo::ShapeFile::Point->new(Y => $y, X => $x, M => $m, Z => $z);
        print "p1=$p1\n";
        print "p2=$p2\n";
        cmp_ok ( $p1, '==', $p2, "Points match");
        cmp_ok ("$p1", 'eq', $txt);
        cmp_ok ("$p2", 'eq', $txt);
    }
}


sub test_files {
    my %data = Geo::ShapeFile::TestHelpers::get_data();
    
    foreach my $base (sort keys %data) {
        foreach my $ext (qw/dbf shp shx/) {
            ok(-f "$dir/$base.$ext", "$ext file exists for $base");
        }
        my $obj = $data{$base}->{object} = Geo::ShapeFile->new("$dir/$base");

        my @expected_fld_names = grep {$_ ne '_deleted'} split /\s+/, $data{$base}{dbf_labels};
        my @got_fld_names = $obj->get_dbf_field_names;

        is_deeply (
            \@expected_fld_names,
            \@got_fld_names,
            "got expected field names for $base",
        );

        # test SHP
        cmp_ok (
            $obj->shape_type_text(),
            'eq',
            $data{$base}->{shape_type},
            "Shape type for $base",
        );
        cmp_ok(
            $obj->shapes(),
            '==',
            $data{$base}->{shapes},
            "Number of shapes for $base"
        );

        # test shapes
        my $nulls = 0;
        subtest "$base has valid records" => sub {
            if (!$obj->records()) {
                ok (1, "$base has no records, so just pass this subtest");
            }

            for my $n (1 .. $obj->shapes()) {
                my($offset, $cl1) = $obj->get_shx_record($n);
                my($number, $cl2) = $obj->get_shp_record_header($n);

                cmp_ok($cl1, '==', $cl2,    "$base($n) shp/shx record content-lengths");
                cmp_ok($n,   '==', $number, "$base($n) shp/shx record ids agree");

                my $shp = $obj->get_shp_record($n);

                if ($shp->shape_type == 0) {
                    $nulls++;
                }

                my $parts = $shp->num_parts;
                my @parts = $shp->parts;
                cmp_ok($parts, '==', scalar(@parts), "$base($n) parts count");

                my $points = $shp->num_points;
                my @points = $shp->points;
                cmp_ok($points, '==', scalar(@points), "$base($n) points count");

                my $undefs = 0;
                foreach my $pnt (@points) {
                    defined($pnt->X) || $undefs++;
                    defined($pnt->Y) || $undefs++;
                }
                ok(!$undefs, "undefined points");

                my $len = length($shp->{shp_data});
                cmp_ok($len, '==', 0, "$base($n) no leftover data");
            }
        };

        ok($nulls == $data{$base}->{nulls});

        # test DBF
        ok($obj->{dbf_version} == 3, "dbf version 3");

        cmp_ok(
            $obj->{dbf_num_records},
            '==',
            $obj->shapes(),
            "$base dbf has record per shape",
        );

        cmp_ok(
            $obj->records(),
            '==',
            $obj->shapes(),
            "same number of shapes and records",
        );

        subtest "$base: can read each record" => sub {
            if (!$obj->records()) {
                ok (1, "$base has no records, so just pass this subtest");
            }

            for my $n (1 .. $obj->shapes()) {
                ok (my $dbf = $obj->get_dbf_record($n), "$base($n) read dbf record");
            }
        };

        #  This is possibly redundant due to get_dbf_field_names check above,
        #  although that does not check against each record.
        my @expected_flds = sort split (/ /, $data{$base}->{dbf_labels});
        subtest "dbf for $base has correct labels" => sub {
            if (!$obj->records()) {
                ok (1, "$base has no records, so just pass this subtest");
            }
            for my $n (1 .. $obj->records()) {
                my %record = $obj->get_dbf_record($n);
                is_deeply (
                    [sort keys %record],
                    \@expected_flds,
                    "$base, record $n",
                );
            }
        };

    }
}


sub test_empty_dbf {
    my $empty_dbf = Geo::ShapeFile::TestHelpers::get_empty_dbf();
    my $obj = Geo::ShapeFile->new($empty_dbf);
    my $records = $obj->records;
    is ($records, 0, 'empty dbf file has zero records');
}
