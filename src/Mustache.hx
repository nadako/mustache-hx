import mustache.*;

class Mustache {
    static var tags = ["{{", "}}"];

    static var tagRe = ~/#|\^|\/|>|\{|&|=|!/;
    static var whiteRe = ~/\s*/;
    static var spaceRe = ~/\s+/;
    static var equalsRe = ~/\s*=/;
    static var curlyRe = ~/\s*\}/;

    static var defaultWriter = new Writer();

    public static inline function clearCache() return defaultWriter.clearCache();
    public static inline function parse(template, ?tags) return defaultWriter.parse(template, tags);
    public static inline function render(template, view, ?partials) return defaultWriter.render(template, view, partials);

    public static function parseTemplate(template:String, ?tags:Array<String>):Array<Token> {
        if (template.length == 0)
            return [];

        var sections = [];     // Stack to hold section tokens
        var tokens:Array<Token> = [];       // Buffer to hold the tokens
        var spaces = [];       // Indices of whitespace tokens on the current line
        var hasTag = false;    // Is there a {{tag}} on the current line?
        var nonSpace = false;  // Is there a non-space char on the current line?

        // Strips all whitespace tokens array for the current line
        // if there was a {{#tag}} on it and otherwise only space.
        function stripSpace() {
            if (hasTag && !nonSpace) {
                while (spaces.length > 0)
                    tokens[spaces.pop()] = null;
            } else {
                spaces = [];
            }

            hasTag = false;
            nonSpace = false;
        }

        var openingTagRe, closingTagRe, closingCurlyRe;
        function compileTags(tagsToCompile:Array<String>) {
            if (tagsToCompile.length != 2)
                throw "Invalid tags: " + tagsToCompile;

            openingTagRe = new EReg(escapeRegExp(tagsToCompile[0]) + '\\s*', "");
            closingTagRe = new EReg('\\s*' + escapeRegExp(tagsToCompile[1]), "");
            closingCurlyRe = new EReg('\\s*' + escapeRegExp('}' + tagsToCompile[1]), "");
        }
        compileTags(tags != null ? tags : Mustache.tags);

        var scanner = new Scanner(template);
        while (!scanner.eos()) {
            var start = scanner.pos;

            // Match any text between tags.
            var value = scanner.scanUntil(openingTagRe);

            if (value.length > 0) {
                for (i in 0...value.length) {
                    var chr = value.charAt(i);

                    if (isWhitespace(chr))
                        spaces.push(tokens.length);
                    else
                        nonSpace = true;

                    tokens.push(['text', chr, start, start + 1]);
                    start += 1;

                    // Check for whitespace on the current line.
                    if (chr == '\n')
                        stripSpace();
                }
            }
            // Match the opening tag.
            if (scanner.scan(openingTagRe).length == 0)
                break;

            hasTag = true;

            // Get the tag type.
            var type = scanner.scan(tagRe);
            if (type.length == 0) type = 'name';
            scanner.scan(whiteRe);

            // Get the tag value.
            if (type == '=') {
                value = scanner.scanUntil(equalsRe);
                scanner.scan(equalsRe);
                scanner.scanUntil(closingTagRe);
            } else if (type == '{') {
                value = scanner.scanUntil(closingCurlyRe);
                scanner.scan(curlyRe);
                scanner.scanUntil(closingTagRe);
                type = '&';
            } else {
                value = scanner.scanUntil(closingTagRe);
            }

            // Match the closing tag.
            if (scanner.scan(closingTagRe).length == 0)
                throw 'Unclosed tag at ${scanner.pos}';

            var token:Token = [ type, value, start, scanner.pos ];
            tokens.push(token);

            if (type == '#' || type == '^') {
                sections.push(token);
            } else if (type == '/') {
                // Check section nesting.
                var openSection = sections.pop();

                if (openSection == null)
                    throw 'Unopened section "$value" at $start';

                if (openSection[1] != value)
                    throw 'Unclosed section "${openSection[1]}" at $start';
            } else if (type == 'name' || type == '{' || type == '&') {
                nonSpace = true;
            } else if (type == '=') {
                // Set the tags for the next time around.
                compileTags(spaceRe.split(value));
            }
        }

        // Make sure there are no open sections when we're done.
        var openSection = sections.pop();
        if (openSection != null)
            throw 'Unclosed section "${openSection[1]}" at ${scanner.pos}';

        return nestTokens(squashTokens(tokens));
    }


    static function squashTokens(tokens:Array<Token>):Array<Token> {
        var squashedTokens = [];

        var lastToken:Token = null;
        for (token in tokens) {
            if (token != null) {
                if (token[0] == 'text' && lastToken != null && lastToken[0] == 'text') {
                    lastToken[1] += token[1];
                    lastToken[3] = token[3];
                } else {
                    squashedTokens.push(token);
                    lastToken = token;
                }
            }
        }

        return squashedTokens;
    }

    static function nestTokens(tokens:Array<Token>):Array<Token> {
        var nestedTokens = [];
        var collector = nestedTokens;
        var sections = [];

        for (token in tokens) {
            switch (token[0]) {
                case '#' | '^':
                    collector.push(token);
                    sections.push(token);
                    collector = token[4] = [];
                case '/':
                    var section = sections.pop();
                    section[5] = token[2];
                    collector = if (sections.length > 0) sections[sections.length - 1][4] else nestedTokens;
                default:
                    collector.push(token);
            }
        }

        return nestedTokens;
    }

    static var escapeRegExpRe = ~/[\-\[\]{}()*+?.,\\\^$|#\s]/g;
    static inline function escapeRegExp(string:String):String {
        return escapeRegExpRe.replace(string, '\\$&');
    }

    static var nonSpaceRe = ~/\S/;
    static inline function isWhitespace(string:String):Bool {
        return !nonSpaceRe.match(string);
    }

    static var entityMap = [
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        "'" => '&#39;',
        '/' => '&#x2F;',
        '`' => '&#x60;',
        '=' => '&#x3D;',
    ];

    static var escapeRe = ~/[&<>"'`=\/]/g;
    public static function escape(string:String):String {
        return escapeRe.map(string, function(re) return entityMap[re.matched(0)]);
    }
}