/// Where the module's movie screen is, for the capability that leads to it and
/// for the module that registers it.
library;

/// The path parameter that holds the movie's id.
const movieIdParameter = 'movieId';

/// The router pattern of the movie screen.
const movieDetailPattern = 'radarr/movies/:$movieIdParameter';

/// The path of the screen of the movie [id].
String movieDetailPath(int id) => 'radarr/movies/$id';
