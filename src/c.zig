// usingnamespace marks that everything in the cImport
// is brought into the namespace of the file and
// pub marks that everything brought in by our
// usingnamespace in public
pub usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
});
