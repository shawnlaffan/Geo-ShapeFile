use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'          => 'Geo::ShapeFile',
    'VERSION_FROM'  => 'lib/Geo/ShapeFile.pm', # finds $VERSION
    'PREREQ_PM'	    => {
        'Carp'       => 0,
        'IO::File'   => 0,
        'Math::Trig' => 0,
    },
    BUILD_REQUIRES => {
        rlib         => 0,
    },
    ($] >= 5.005 ? (
        ABSTRACT_FROM => 'lib/Geo/ShapeFile.pm',
        AUTHOR        => 'Jason Kohles <email@jasonkohles.com>',
    ) : ()),
);
