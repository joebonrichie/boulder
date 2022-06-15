/* SPDX-License-Identifier: Zlib */

/**
 * Chef - Build Management
 *
 * Generation and manipulation of source recipe files that can then be consumed
 * by boulder.
 *
 * Authors: © 2020-2022 Serpent OS Developers
 * License: ZLib
 */

module chef.build;

/**
 * Supported build system types.
 */
public enum BuildType : string
{
    /**
     * Uses configure/make/install routine
     */
    Autotools = "autotools",

    /**
     * Unsupported tooling
     */
    Unknown = "unknown",
}

/**
 * Any BuildPattern implementation must have the
 * following members to be valid. For lightweight
 * usage we actually use structs not class implementations.
 */
public interface Build
{
    /**
     * Implement the `setup` step
     */
    string setup();

    /**
     * Implement the `build` step
     */
    string build();

    /**
     * Implement the `install` step
     */
    string install();

    /**
     * Implement the `check` step
     */
    string check();
}