/*
 * SPDX-FileCopyrightText: Copyright © 2020-2022 Serpent OS Developers
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * Module Name (use e.g. 'moss.core.foo.bar')
 *
 * Module Description (FIXME)
 *
 * In package.d files containing only imports and nothing else,
 * 'Module namespace imports.' is sufficient description.
 *
 * Authors: Copyright © 2020-2022 Serpent OS Developers
 * License: Zlib
 */

module boulder.controller;

import boulder.buildjob;
import boulder.stages;
import moss.core.mounts;
import moss.core.util : computeSHA256;
import moss.fetcher;
import moss.format.source;
import std.algorithm : filter;
import std.exception : enforce;
import std.experimental.logger;
import std.file : exists, rmdirRecurse, thisExePath;
import std.parallelism : totalCPUs;
import std.path : absolutePath, baseName, buildNormalizedPath, dirName, buildNormalizedPath;
import std.range : take;
import std.string : format;

/**
 * This is the main entry point for all build commands which will be dispatched
 * to mason in the chroot environment via moss-container.
 */
public final class Controller : StageContext
{
    @disable this();

    /**
     * Construct a new Controller
     *
     * Params:
     *      confinement = Enable confined builds
     */
    this(string outputDir, string architecture, bool confinement)
    {
        this._architecture = architecture;
        this._confinement = confinement;

        /* Relative locations for moss/moss-container */
        auto binDir = thisExePath.dirName;
        _mossBinary = binDir.buildNormalizedPath("moss").absolutePath;
        _containerBinary = binDir.buildNormalizedPath("moss-container").absolutePath;

        _outputDirectory = outputDir.absolutePath;

        /* Only need moss/moss-container for confined builds */
        if (confinement)
        {
            if (!mossBinary.exists)
            {
                fatalf("Cannot find `moss` at: %s", _mossBinary);
            }
            if (!containerBinary.exists)
            {
                fatalf("Cannot find `moss-container` at: %s", _containerBinary);
            }

            tracef("moss: %s", _mossBinary);
            tracef("moss-container: %s", _containerBinary);
        }
        else
        {
            warning("RUNNING BOULDER WITHOUT CONFINEMENT");
        }

        _upstreamCache = new UpstreamCache();
        _fetcher = new FetchController(totalCPUs >= 4 ? 3 : 1);
        _fetcher.onComplete.connect(&onFetchComplete);
        _fetcher.onFail.connect(&onFetchFail);
    }

    pure override @property immutable(string) outputDirectory() @safe @nogc nothrow const
    {
        return _outputDirectory;
    }

    /**
     * Architecture target
     *
     * Returns: the current architecture target which may be "native"
     */
    pure override @property immutable(string) architecture() @safe @nogc nothrow const
    {
        return _architecture;
    }

    /** 
     * Confinement status
     *
     * Returns: false if the CLI has `-u` passed as a flag
     */
    pure override @property bool confinement() @safe @nogc nothrow const
    {
        return _confinement;
    }

    /**
     * Return our job
     */
    pure override @property const(BuildJob) job() @safe @nogc nothrow const
    {
        return _job;
    }

    /**
     * Return moss path
     */
    pure override @property immutable(string) mossBinary() @safe @nogc nothrow const
    {
        return _mossBinary;
    }

    /**
     * Return container path
     */
    pure override @property immutable(string) containerBinary() @safe @nogc nothrow const
    {
        return _containerBinary;
    }

    pure override @property UpstreamCache upstreamCache() @safe @nogc nothrow
    {
        return _upstreamCache;
    }

    /**
     * Returns: The FetchContext
     */
    pure override @property FetchController fetcher() @safe @nogc nothrow
    {
        return _fetcher;
    }

    /**
     * Begin the build process for a specific recipe
     */
    void build(in string filename)
    {
        auto fi = File(filename, "r");
        recipe = new Spec(fi);
        recipe.parse();

        _job = new BuildJob(recipe, filename);
        scope (exit)
        {
            fi.close();
        }

        int stageIndex = 0;
        int nStages = cast(int) boulderStages.length;

        build_loop: while (true)
        {
            /* Dun dun dun */
            if (stageIndex > nStages - 1)
            {
                break build_loop;
            }

            auto stage = boulderStages[stageIndex];
            enforce(stage.functor !is null);

            tracef("Stage begin: %s", stage.name);
            StageReturn result = StageReturn.Failure;
            try
            {
                result = stage.functor(this);
            }
            catch (Exception e)
            {
                errorf("Exception: %s", e.message);
                result = StageReturn.Failure;
            }

            /* Take the early fail */
            if (failFlag == true)
            {
                result = StageReturn.Failure;
            }

            final switch (result)
            {
            case StageReturn.Failure:
                errorf("Stage failure: %s", stage.name);
                break build_loop;
            case StageReturn.Success:
                infof("Stage success: %s", stage.name);
                ++stageIndex;
                break;
            case StageReturn.Skipped:
                tracef("Stage skipped: %s", stage.name);
                ++stageIndex;
                break;
            }
        }

        /* Unmount anything mounted */
        foreach_reverse (ref m; mountPoints)
        {
            m.unmountFlags = UnmountFlags.Force | UnmountFlags.Detach;
            auto err = m.unmount();
            if (!err.isNull())
            {
                errorf("Unmount failure: %s (%s)", m.target, err.get.toString);
            }
        }
    }

    /**
     * Add mounts to track list to unmount them
     */
    void addMount(in Mount mount) @safe nothrow
    {
        mountPoints ~= mount;
    }

private:

    void onFetchComplete(in Fetchable f, long statusCode)
    {
        /* Validate the statusCode */
        auto ud = fetchableToUpstream(f);
        if (statusCode != 200)
        {
            onFetchFail(f, "Download finished with status code: %d".format(statusCode));
            return;
        }
        /* Verify hash */
        auto foundHash = computeSHA256(f.destinationPath, true);
        if (foundHash != ud.plain.hash)
        {
            onFetchFail(f, "Expected hash: %s, found '%s'".format(ud.plain.hash, foundHash));
            return;
        }
        /* Promote the source now */
        upstreamCache.promote(ud);
    }

    /**
     * Handle failed downloads
     */
    void onFetchFail(in Fetchable f, in string failMsg)
    {
        fetcher.clear();
        failFlag = true;
        errorf("Download failure: %s (reason: %s)", f.sourceURI, failMsg);
    }

    /**
     * Return a matching UpstreamDefinition for the input Fetchable
     */
    auto fetchableToUpstream(in Fetchable f)
    {
        return job.recipe.upstreams.values.filter!(
                (u) => u.plain.hash == f.destinationPath.baseName).take(1).front;
    }

    string _mossBinary;
    string _containerBinary;
    string _architecture;
    string _outputDirectory;

    Spec* recipe = null;
    BuildJob _job;
    UpstreamCache _upstreamCache = null;
    FetchController _fetcher = null;
    bool failFlag = false;
    bool _confinement;

    Mount[] mountPoints;
}
