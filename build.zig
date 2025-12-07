const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const image_lib = b.addStaticLibrary(.{
        .name = "image",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/image.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(image_lib);

    const exe = b.addExecutable(.{
        .name = "imglib",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const commonlib = b.dependency("common", .{});
    exe.root_module.addImport("common", commonlib.module("common"));

    const image_module = b.addModule("image", .{
        .root_source_file = b.path("src/image.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bmp_image_module = b.addModule("bmp_image", .{
        .root_source_file = b.path("src/bmp_image.zig"),
        .target = target,
        .optimize = optimize,
    });

    const jpeg_image_module = b.addModule("jpeg_image", .{
        .root_source_file = b.path("src/jpeg_image.zig"),
        .target = target,
        .optimize = optimize,
    });

    const png_image_module = b.addModule("png_image", .{
        .root_source_file = b.path("src/png_image.zig"),
        .target = target,
        .optimize = optimize,
    });

    const svg_image_module = b.addModule("svg_image", .{
        .root_source_file = b.path("src/svg_image.zig"),
        .target = target,
        .optimize = optimize,
    });

    bmp_image_module.addImport("common", commonlib.module("common"));
    jpeg_image_module.addImport("common", commonlib.module("common"));
    png_image_module.addImport("common", commonlib.module("common"));
    svg_image_module.addImport("common", commonlib.module("common"));
    image_module.addImport("common", commonlib.module("common"));
    exe.root_module.addImport("image", image_module);
    exe.root_module.addImport("bmp_image", bmp_image_module);
    exe.root_module.addImport("jpeg_image", jpeg_image_module);
    exe.root_module.addImport("png_image", png_image_module);
    exe.root_module.addImport("svg_image", svg_image_module);
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const bmp_lib_unit_tests = b.addTest(.{
        .name = "bmp_image",
        .root_module = bmp_image_module,
    });

    const run_bmp_lib_unit_tests = b.addRunArtifact(bmp_lib_unit_tests);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const png_lib_unit_tests = b.addTest(.{
        .name = "png_image",
        .root_module = png_image_module,
    });

    const run_png_lib_unit_tests = b.addRunArtifact(png_lib_unit_tests);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const jpeg_lib_unit_tests = b.addTest(.{
        .name = "jpeg_image",
        .root_module = jpeg_image_module,
    });

    const run_jpeg_lib_unit_tests = b.addRunArtifact(jpeg_lib_unit_tests);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const image_lib_unit_tests = b.addTest(.{
        .name = "image",
        .root_module = image_module,
    });

    const run_image_lib_unit_tests = b.addRunArtifact(image_lib_unit_tests);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const svg_lib_unit_tests = b.addTest(.{
        .name = "svg_image",
        .root_module = svg_image_module,
    });

    const run_svg_lib_unit_tests = b.addRunArtifact(svg_lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_bmp_lib_unit_tests.step);
    test_step.dependOn(&run_png_lib_unit_tests.step);
    test_step.dependOn(&run_jpeg_lib_unit_tests.step);
    test_step.dependOn(&run_svg_lib_unit_tests.step);
    test_step.dependOn(&run_image_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const svg_test = b.step("svg", "Run unit tests");
    svg_test.dependOn(&run_svg_lib_unit_tests.step);
}
