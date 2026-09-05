package arcade;

import arcade.SortBodies;

/**
 * A Group is a container for multiple physics bodies.
 * Groups can be used for efficient collision detection between sets of bodies.
 */
class Group implements Collidable {

    /** Array of Body objects contained in this group. */
    public var objects:Array<Body> = [];

    /** The sorting direction for bodies in this group. */
    public var sortDirection:SortDirection = SortDirection.INHERIT;

    /**
     * The direction this group is currently sorted in, or `NONE` if the cached
     * ordering is not valid.
     */
    var cachedSortDirection:SortDirection = SortDirection.NONE;

    /**
     * A spatial index over this group's bodies, owned by the group and rebuilt
     * at most once per frame rather than once per collision call.
     */
    var cachedQuadTree:QuadTree = null;

    /** Whether `cachedQuadTree` reflects the bodies at their current positions. */
    var cachedQuadTreeValid:Bool = false;

    /** How many collision queries have been made since the bodies last moved. */
    var queriesSinceInvalidate:Int = 0;

    /**
     * The widest and tallest body in this group, as of the last sort.
     *
     * The pair loops use this to know how far back along the sort axis a body
     * could still reach. Sorting orders bodies by their near edge, so without a
     * bound on size there is no safe point at which to stop looking.
     */
    public var maxBodyWidth(default, null):Float = 0;
    public var maxBodyHeight(default, null):Float = 0;

    public function new() {

    }

    /**
     * Marks this group's cached ordering and spatial index as out of date.
     *
     * Called automatically when the group's membership changes and when a
     * member body runs `preUpdate`, which covers the normal update cycle. Call
     * it yourself if you move a body directly without going through
     * `preUpdate`, otherwise collisions in that frame may be resolved against
     * the previous positions.
     */
    inline public function invalidate():Void {

        cachedSortDirection = SortDirection.NONE;
        cachedQuadTreeValid = false;
        queriesSinceInvalidate = 0;

    }

    /**
     * Records a collision query against this group and reports whether it is
     * worth answering from a spatial index.
     *
     * Building a tree over N bodies costs more than the single linear scan it
     * would replace, so the first query after the bodies move is answered by
     * scanning. From the second query onward the tree is built once and reused
     * for the rest of the frame, which is where it pays for itself.
     */
    inline public function useQuadTreeForNextQuery():Bool {

        //  Capped rather than free running: a static group can go many frames
        //  without being invalidated, and the counter only ever needs to
        //  distinguish "first query" from "not the first query"
        if (queriesSinceInvalidate <= 1) {
            queriesSinceInvalidate++;
        }
        return queriesSinceInvalidate > 1;

    }

    /**
     * Whether the group's bodies are already ordered in the given direction,
     * so that the sort can be skipped.
     */
    inline public function isSortedBy(direction:SortDirection):Bool {

        return direction != SortDirection.NONE && cachedSortDirection == direction;

    }

    /**
     * Records that the group has just been sorted in the given direction.
     */
    public function markSortedBy(direction:SortDirection):Void {

        cachedSortDirection = direction;

        var widest:Float = 0;
        var tallest:Float = 0;
        for (i in 0...objects.length) {
            var body = objects[i];
            if (body.width > widest) widest = body.width;
            if (body.height > tallest) tallest = body.height;
        }
        maxBodyWidth = widest;
        maxBodyHeight = tallest;

    }

    /**
     * Returns this group's spatial index, rebuilding it only when the bodies
     * have moved since it was last built.
     *
     * The tree belongs to the group and is reused frame after frame, so a
     * collision call no longer pays to build one for a single query.
     *
     * @param x Bounds of the world the tree should cover.
     * @param y Bounds of the world the tree should cover.
     * @param width Bounds of the world the tree should cover.
     * @param height Bounds of the world the tree should cover.
     * @param maxObjects Maximum number of bodies per quad.
     * @param maxLevels Maximum number of subdivisions.
     */
    public function getQuadTree(x:Float, y:Float, width:Float, height:Float, maxObjects:Int, maxLevels:Int):QuadTree {

        if (cachedQuadTree == null) {
            cachedQuadTree = new QuadTree(null, x, y, width, height, maxObjects, maxLevels);
            cachedQuadTreeValid = false;
        }

        if (!cachedQuadTreeValid) {
            //  reset() already recycles the child nodes and empties the arrays,
            //  so there is no need to clear() first
            cachedQuadTree.reset(x, y, width, height, maxObjects, maxLevels);
            cachedQuadTree.populate(objects);
            cachedQuadTreeValid = true;
        }

        return cachedQuadTree;

    }

    /**
     * Adds a body to this group.
     *
     * @param body The body to add to the group.
     */
    public function add(body:Body):Void {

        var index = objects.indexOf(body);
        if (index != -1) {
            trace('[warning] Cannot add body $body to group, already inside group');
        }
        else {
            objects.push(body);
            invalidate();
        }

        if (body.groups != null) {
            var groupIndex = body.groups.indexOf(this);
            if (groupIndex == -1) {
                body.groups.push(this);
            }
        }
        else {
            body.groups = [this];
        }

    }

    /**
     * Removes a body from this group.
     *
     * @param body The body to remove from the group.
     */
    public function remove(body:Body):Void {

        var index = objects.indexOf(body);
        if (index != -1) {
            objects.splice(index, 1);
            invalidate();
        }
        else {
            trace('[warning] Cannot remove body $body from group, index is -1');
        }

        if (body.groups != null) {
            var groupIndex = body.groups.indexOf(this);
            if (groupIndex != -1) {
                body.groups.splice(groupIndex, 1);
            }
        }

    }

    /**
     * Sorts the bodies in this group from left to right based on their x position.
     */
    public function sortLeftRight() {

        SortBodiesLeftRight.sort(objects);

    }

    /**
     * Sorts the bodies in this group from right to left based on their x position.
     */
    public function sortRightLeft() {

        SortBodiesRightLeft.sort(objects);

    }

    /**
     * Sorts the bodies in this group from top to bottom based on their y position.
     */
    public function sortTopBottom() {

        SortBodiesTopBottom.sort(objects);

    }

    /**
     * Sorts the bodies in this group from bottom to top based on their y position.
     */
    public function sortBottomTop() {

        SortBodiesBottomTop.sort(objects);

    }

}
