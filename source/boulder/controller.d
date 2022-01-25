/*
 * This file is part of boulder.
 *
 * Copyright © 2020-2022 Serpent OS Developers
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

module boulder.controller;

import moss.core.platform : platform;
import moss.format.source;
import std.process;
import std.path : buildPath;
import std.stdio : File, writeln;
import std.string : format;

immutable static private auto SharedRootBase = "/var/cache/boulder";

enum RecipeStage
{
    None = 0,
    Resolve,
    FetchSources,
    ConstructRoot,
    RunBuild,
    Failed,
    Complete,
}

/**
 * Encapsulate some basic directory properties
 */
private struct Container
{
    /** Installation root for the container */
    string root;

    /** Build directory (where we .. build.) */
    string build;

    /** Ccache directory (global shared) */
    string ccache;

    /** Output directory (bind-rw) */
    string output;

    /** Recipe directory (bind-ro) */
    string input;

    this(scope Spec* spec)
    {
        auto p = platform();

        /* Reusable path component */
        auto subpath = format!"%s-%s-%d-%s"(spec.source.name,
                spec.source.versionIdentifier, spec.source.release, p.name);

        root = SharedRootBase.buildPath("root", subpath);
        build = SharedRootBase.buildPath("build", subpath);
        ccache = SharedRootBase.buildPath("ccache");
    }
}

/**
 * This is the main entry point for all build commands which will be dispatched
 * to mason in the chroot environment via moss-container.
 */
public final class Controller
{
    this()
    {
    }

    /**
     * Begin the build process for a specific recipe
     */
    void build(in string filename)
    {
        auto fi = File(filename, "r");
        recipe = new Spec(fi);
        recipe.parse();
        container = Container(recipe);
        scope (exit)
        {
            fi.close();
        }

        build_loop: while (true)
        {
            final switch (stage)
            {
            case RecipeStage.None:
                stage = RecipeStage.Resolve;
                resolveDependencies();
                break;
            case RecipeStage.Resolve:
                stage = RecipeStage.FetchSources;
                break;
            case RecipeStage.FetchSources:
                stage = RecipeStage.ConstructRoot;
                break;
            case RecipeStage.ConstructRoot:
                //constructRoot();
                stage = RecipeStage.RunBuild;
                break;
            case RecipeStage.RunBuild:
                performBuild();
                break;
            case RecipeStage.Failed:
            case RecipeStage.Complete:
                break build_loop;
            }
        }
    }

private:

    /**
     * Use moss to construct a new rootfs
     */
    void constructRoot()
    {
        auto cmd = ["install", "-D", container.root] ~ buildDeps;

        auto pid = spawnProcess(mossBinary ~ cmd);
        auto exitCode = pid.wait();
        if (exitCode != 0)
        {
            stage = RecipeStage.Failed;
        }
        else
        {
            stage = RecipeStage.RunBuild;
        }
    }

    /**
     * Invoke mason via moss-container
     */
    void performBuild()
    {
        auto cmd = ["--fakeroot", "-d", container.root, "--", "ls", "-la"];
        auto pid = spawnProcess(containerBinary ~ cmd);
        auto exitCode = pid.wait();
        if (exitCode != 0)
        {
            stage = RecipeStage.Failed;
        }
        else
        {
            stage = RecipeStage.Complete;
        }
    }

    void resolveDependencies()
    {
        buildDeps = recipe.rootBuild.buildDependencies;
    }

    RecipeStage stage = RecipeStage.None;
    string[] buildDeps;

    /* TEMP */
    string mossBinary = "../moss/bin/moss";
    string containerBinary = "../moss-container/moss-container";

    Spec* recipe = null;
    Container container;
}
