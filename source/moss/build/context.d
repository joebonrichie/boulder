/*
 * This file is part of moss.
 *
 * Copyright © 2020 Serpent OS Developers
 *
 * This software is provided 'as-is', without any express or implied
 * warranty. In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

module moss.build.context;

import moss.format.source.macros;
import moss.format.source.spec;
import moss.format.source.script;

/**
 * The BuildContext holds global configurations and variables needed to complete
 * all builds.
 */
struct BuildContext
{
    /**
     * Construct a new BuildContect
     */
    this(Spec* spec, string rootDir)
    {
        import std.conv : to;

        this._spec = spec;
        this._rootDir = rootDir;

        this.loadMacros();

        /* Basic metadata exposed only */
        sbuilder.addDefinition("name", spec.source.name);
        sbuilder.addDefinition("version", spec.source.versionIdentifier);
        sbuilder.addDefinition("release", to!string(spec.source.release));

        // TODO: Take from file.
        sbuilder.addDefinition("libsuffix", "");
        sbuilder.addDefinition("prefix", "/usr");
        sbuilder.addDefinition("bindir", "%(prefix)/bin");
        sbuilder.addDefinition("sbindir", "%(prefix)/sbin");
        sbuilder.addDefinition("includedir", "%(prefix)/include");
        sbuilder.addDefinition("datadir", "%(prefix)/share");
        sbuilder.addDefinition("localedir", "%(datadir)/locale");
        sbuilder.addDefinition("infodir", "%(datadir)/info");
        sbuilder.addDefinition("mandir", "%(datadir)/man");
        sbuilder.addDefinition("docdir", "%(datadir)/doc");
        sbuilder.addDefinition("localstatedir", "/var");
        sbuilder.addDefinition("runstatedir", "/run");
        sbuilder.addDefinition("sysconfdir", "/etc");
        sbuilder.addDefinition("osconfdir", "%(datadir)/defaults");
        sbuilder.addDefinition("libdir", "%(prefix)/lib%(libsuffix)");
        sbuilder.addDefinition("libexecdir", "%(libdir)/%(name)");
    }

    /**
     * Return reference to underlying ScriptBuilder so that it may be
     * cloned.
     */
    pure final @property ref auto script() @safe @nogc nothrow
    {
        return sbuilder;
    }

    /**
     * Return the root directory
     */
    pure final @property const string rootDir() @safe @nogc nothrow
    {
        return _rootDir;
    }

    /**
     * Return the underlying specfile
     */
    pure final @property Spec* spec() @safe @nogc nothrow
    {
        return _spec;
    }

    /**
     * Prepare a ScriptBuilder
     */
    final void prepareScripts(ref ScriptBuilder builder, string architecture)
    {
        import std.stdio : writefln;

        foreach (ref k, v; macroFiles)
        {
            writefln("Inserting macro file: %s", k);
        }
    }

private:

    /**
     * Load all supportable macros
     */
    final void loadMacros()
    {
        import std.file : exists, thisExePath;
        import std.path : buildPath, dirName;
        import moss.platform;
        import std.string : format;
        import std.exception : enforce;

        MacroFile* file = null;

        string resourceDir = "/usr/share/moss/macros";
        string actionDir = null;
        string localDir = dirName(thisExePath).buildPath("..", "data", "macros");

        /* Prefer local macros */
        if (localDir.exists())
        {
            resourceDir = localDir;
        }

        auto plat = platform();
        actionDir = resourceDir.buildPath("actions");

        /* Architecture specific YMLs that MUST exist */
        string baseYml = resourceDir.buildPath("base.yml");
        string nativeYml = resourceDir.buildPath("%s.yml".format(plat.name));
        string emulYml = resourceDir.buildPath("emul32", "%s.yml".format(plat.name));

        enforce(baseYml.exists, baseYml ~ " file cannot be found");
        enforce(nativeYml.exists, nativeYml ~ " cannot be found");
        if (plat.emul32)
        {
            enforce(emulYml.exists, emulYml ~ " cannot be found");
        }

        /* Load base YML */
        file = new MacroFile(File(baseYml));
        file.parse();
        macroFiles["base"] = file;

        /* Load arch specific */
        file = new MacroFile(File(nativeYml));
        file.parse();
        macroFiles[plat.name] = file;

        /* emul32? */
        if (plat.emul32)
        {
            file = new MacroFile(File(emulYml));
            file.parse();
            macroFiles["emul32/%s".format(plat.name)] = file;
        }

        if (!actionDir.exists)
        {
            return;
        }
    }

    ScriptBuilder sbuilder;
    string _rootDir;
    Spec* _spec;
    MacroFile*[string] macroFiles;
}