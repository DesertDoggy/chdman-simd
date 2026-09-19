#include "chdman_lib.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

/*
 * chdman.cpp's own `main` is compiled (see Makefile.chdman_lib) with -Dmain=chdman_cli_entry,
 * which renames its entry point at the preprocessor level -- the .cpp file itself is never
 * modified. This lets chdman's real, unmodified command dispatch (command lookup in
 * s_commands[], option parsing into parameters_map, calling the matching do_* handler, and
 * catching std::error_condition/fatal_error/std::exception into a return code -- see
 * src/tools/chdman.cpp's main()) be called as an ordinary function instead of being the
 * process entry point.
 *
 * Deliberately NOT extern "C": a function literally named `main` is exempt from C++ name
 * mangling by the standard, but once renamed to chdman_cli_entry it's an ordinary function
 * and IS mangled like any other -- so this declaration must use plain C++ linkage (matching
 * how chdman.cpp's definition actually gets compiled) rather than extern "C", or the two
 * won't agree on a symbol name.
 */
int chdman_cli_entry(int argc, char* argv[]);

int chdman_run(int argc, const char* const* argv, char** out_log)
{
    // chdman's main() expects argv[0] to be the program name (used only in help/usage
    // text) and argv[1] to be the command name. The public API here takes just the
    // command + options (no program name), so prepend one.
    std::vector<std::string> owned;
    owned.reserve(static_cast<size_t>(argc) + 1);
    owned.emplace_back("chdman");
    for (int i = 0; i < argc; ++i)
        owned.emplace_back(argv[i] ? argv[i] : "");

    std::vector<char*> mutable_argv;
    mutable_argv.reserve(owned.size());
    for (auto& s : owned)
        mutable_argv.push_back(s.data());

    std::ostringstream captured;
    std::streambuf* old_cout = std::cout.rdbuf(captured.rdbuf());
    std::streambuf* old_cerr = std::cerr.rdbuf(captured.rdbuf());

    int rc = 1;
    try
    {
        rc = chdman_cli_entry(static_cast<int>(mutable_argv.size()), mutable_argv.data());
    }
    catch (...)
    {
        captured << "chdman_run: unhandled exception escaped chdman's command dispatch\n";
        rc = 1;
    }

    std::cout.rdbuf(old_cout);
    std::cerr.rdbuf(old_cerr);

    if (out_log)
    {
        const std::string text = captured.str();
        char* buf = static_cast<char*>(std::malloc(text.size() + 1));
        if (buf)
            std::memcpy(buf, text.c_str(), text.size() + 1);
        *out_log = buf;
    }

    return rc;
}

void chdman_free_log(char* log)
{
    std::free(log);
}
